// T-091: bill splits and reimbursements (FR-XFR-04…09, BR-XFR-04…08,
// EC-37/39/40; domain-algorithms §5). The deciding rules are in
// `zaghlol_domain/transfers/splits.dart`.
//
// Safety rules (money is never counted twice, never converted):
// - Every call is one database transaction. The schema's triggers cap the
//   links of an expense and of an incoming transfer at their amounts, so a
//   racing writer can at worst fail with `conflict`, never over-offset.
// - Same currency only; a link stores the amount in the expense's currency.
// - A grant is the plan's `min(requested, expense room, friend's unsettled
//   share, transfer left)`; whatever is not granted stays income, and the
//   result lists every clamp and rejection, so nothing is silent.
// - Unassigning deletes only a `reimbursement` link; the transfer then
//   counts as income again because income is computed from the links.
// - EC-40: `repairForNewAmount` must run in the editing transaction BEFORE
//   the amount is written (the schema's trigger refuses a shrink below the
//   links). It removes the newest links until the rest fits.
//
// Failures are code-only; nothing here logs and no payload carries amounts,
// names or messages.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/offset_links_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/daos/transfers_dao.dart';
import '../../../core/db/db_errors.dart';
import '../data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import 'transactions_changed_event.dart';

final class ReimbursementException extends SafeException {
  ReimbursementException(super.code);

  static const String invalid = 'REIMB_INVALID';
  static const String notFound = 'REIMB_NOT_FOUND';

  /// The transaction is not a live expense / posted incoming transfer.
  static const String notEligible = 'REIMB_NOT_ELIGIBLE';

  /// The shares would exceed the expense (BR-XFR-04).
  static const String sharesExceed = 'REIMB_SHARES_EXCEED';

  /// A link for this expense and transfer exists; unassign it first.
  static const String alreadyLinked = 'REIMB_ALREADY_LINKED';

  /// Another writer changed the sums first (trigger or UNIQUE clash).
  static const String conflict = 'REIMB_CONFLICT';
}

/// One "put this much on that expense" the user asked for.
final class AssignRequest {
  const AssignRequest({
    required this.expenseId,
    required this.amountMinor,
    this.participantId,
  });

  final String expenseId;
  final int amountMinor;
  final String? participantId;
}

final class AssignResult {
  const AssignResult({
    required this.plan,
    required this.linkIds,
    required this.event,
  });

  /// Grants (with clamps), rejections and the income remainder.
  final ReimbursementPlan plan;

  /// Ids of the links written, in the order of `plan.grants`.
  final List<String> linkIds;

  /// Cycles and accounts to refresh; null when nothing was written.
  final TransactionsChanged? event;
}

final class RepairResult {
  const RepairResult({
    required this.removedLinkIds,
    required this.sharesExceedAmount,
    required this.event,
  });

  /// Links removed (newest first) so the new amount fits; non-empty means
  /// the user gets a notice (EC-40).
  final List<String> removedLinkIds;

  /// Participants' shares now add up to more than the new amount; the UI
  /// asks the user to fix them.
  final bool sharesExceedAmount;

  final TransactionsChanged? event;
}

class Reimbursements {
  Reimbursements(
    this._db, {
    required this._loadSchedule,
    Clock? clock,
    IdGenerator? newId,
    this._events,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4,
       _txns = TransactionsDao(_db),
       _links = OffsetLinksDao(_db),
       _parts = SplitParticipantsDao(_db);

  final AppDatabase _db;
  final Future<PaydaySchedule> Function() _loadSchedule;
  final Clock _now;
  final IdGenerator _newId;
  final DomainEventBus? _events;
  final TransactionsDao _txns;
  final OffsetLinksDao _links;
  final SplitParticipantsDao _parts;

  static const int maxNameRunes = 64;
  static const int maxRequests = 50;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  // ------------------------------------------------------- participants

  /// Marks [expenseId] as shared with [name], who owes [shareMinor]
  /// (FR-XFR-04). Σ shares may not exceed the expense. Returns the id.
  Future<String> addParticipant(
    String expenseId,
    String name,
    int shareMinor,
  ) async {
    final clean = _name(name);
    if (shareMinor < 0) _invalid();
    final id = _newId();
    final now = _nowMs();
    await _guard(
      () => _txns.inTransaction(() async {
        final e = await _expense(expenseId);
        final others = await _parts.forExpense(expenseId);
        _checkShares(e, [for (final p in others) p.shareMinor, shareMinor]);
        await _parts.insert(
          SplitParticipantsCompanion.insert(
            id: id,
            expenseTxnId: expenseId,
            name: clean,
            shareMinor: shareMinor,
            createdAt: now,
          ),
        );
      }),
    );
    return id;
  }

  /// Changes a participant's share. Repayments already attributed to them
  /// stay; the unsettled amount floors at zero.
  Future<void> updateShare(String participantId, int shareMinor) async {
    if (participantId.isEmpty || shareMinor < 0) _invalid();
    await _guard(
      () => _txns.inTransaction(() async {
        final p = await _participant(participantId);
        final e = await _expense(p.expenseTxnId);
        final all = await _parts.forExpense(p.expenseTxnId);
        _checkShares(e, [
          for (final q in all)
            q.id == participantId ? shareMinor : q.shareMinor,
        ]);
        if (await _parts.updateShare(participantId, shareMinor) != 1) {
          _notFound();
        }
      }),
    );
  }

  /// Removes a participant; links naming them keep their amount and lose
  /// the name (the schema's `ON DELETE SET NULL`).
  Future<void> removeParticipant(String participantId) async {
    if (participantId.isEmpty) _invalid();
    final n = await _guard(() => _parts.deleteById(participantId));
    if (n != 1) _notFound();
  }

  /// Per participant: what they still owe (FR-XFR-05), in expense order.
  Future<Map<String, Money>> unsettled(String expenseId) async {
    final e = await _txns.byId(expenseId);
    if (e == null) _notFound();
    final cur = Currency.of(e.currency);
    final out = <String, Money>{};
    for (final p in await _parts.forExpense(expenseId)) {
      out[p.id] = unsettledShare(
        Money(cur, p.shareMinor),
        Money(cur, await _repaid(p.id)),
      );
    }
    return out;
  }

  // -------------------------------------------------- assign / unassign

  /// Assigns the incoming transfer [sourceId] to expenses (FR-XFR-06/07).
  /// The plan clamps to what each expense, named friend and the transfer
  /// have left; the rest of the transfer stays income (BR-XFR-06).
  Future<AssignResult> assign(
    String sourceId,
    List<AssignRequest> requests,
  ) async {
    if (sourceId.isEmpty || requests.isEmpty || requests.length > maxRequests) {
      _invalid();
    }
    final schedule = await _loadSchedule();
    final now = _nowMs();
    final result = await _guard(
      () => _txns.inTransaction(() async {
        final src = await _txns.byId(sourceId);
        if (src == null ||
            src.deletedAt != null ||
            src.status != 'posted' ||
            src.isInternal != 0 ||
            src.amountMinor <= 0 ||
            (src.direction != 'income' && src.direction != 'transfer_in')) {
          throw ReimbursementException(ReimbursementException.notEligible);
        }
        final cur = Currency.of(src.currency);
        final left = src.amountMinor - await _links.linkedFromSource(sourceId);
        final rooms = <ExpenseRoom>[];
        for (final q in requests) {
          if (q.amountMinor <= 0) _invalid();
          final e = await _txns.byId(q.expenseId);
          if (e == null ||
              e.deletedAt != null ||
              e.direction != 'expense' ||
              e.isInternal != 0 ||
              e.currency != src.currency) {
            // Unknown or other-currency expenses become plan rejections.
            continue;
          }
          if (await _linkExists(q.expenseId, sourceId)) {
            throw ReimbursementException(ReimbursementException.alreadyLinked);
          }
          final partRoom = <String, Money>{};
          for (final p in await _parts.forExpense(q.expenseId)) {
            partRoom[p.id] = unsettledShare(
              Money(cur, p.shareMinor),
              Money(cur, await _repaid(p.id)),
            );
          }
          rooms.add(
            ExpenseRoom(
              expenseId: q.expenseId,
              remaining: Money(
                cur,
                e.amountMinor - await _links.linkedToExpense(q.expenseId),
              ),
              participantRemaining: partRoom,
            ),
          );
        }
        final plan = planReimbursement(
          sourceRemaining: Money(cur, left < 0 ? 0 : left),
          requests: [
            for (final q in requests)
              AllocationRequest(
                expenseId: q.expenseId,
                amount: Money(cur, q.amountMinor),
                participantId: q.participantId,
              ),
          ],
          rooms: rooms,
        );
        if (plan.grants.isEmpty) {
          return AssignResult(plan: plan, linkIds: const [], event: null);
        }
        final ids = <String>[];
        for (final g in plan.grants) {
          final id = _newId();
          ids.add(id);
          await _links.insert(
            OffsetLinksCompanion.insert(
              id: id,
              kind: 'reimbursement',
              expenseTxnId: g.expenseId,
              sourceTxnId: sourceId,
              amountMinor: g.granted.minor,
              participantId: Value(g.participantId),
              createdAt: now,
            ),
          );
        }
        await _resolveSuggestion(sourceId, 'linked', now);
        final event = await _eventFor(schedule, [
          sourceId,
          for (final g in plan.grants) g.expenseId,
        ]);
        return AssignResult(plan: plan, linkIds: ids, event: event);
      }),
    );
    final ev = result.event;
    if (ev != null) _events?.publish(ev);
    return result;
  }

  /// Unassigns a reimbursement (FR-XFR-09). Refund links are not touched
  /// here (use `RefundMatching.unlink`). The transfer is income again.
  Future<TransactionsChanged> unassign(String linkId) async {
    if (linkId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final event = await _guard(
      () => _txns.inTransaction(() async {
        final rows = await _db
            .customSelect(
              'SELECT expense_txn_id, source_txn_id, kind FROM offset_links '
              'WHERE id = ?1',
              variables: [Variable.withString(linkId)],
              readsFrom: {_db.offsetLinks},
            )
            .get();
        if (rows.isEmpty) _notFound();
        final r = rows.single;
        if (r.read<String>('kind') != 'reimbursement') {
          throw ReimbursementException(ReimbursementException.notEligible);
        }
        final ev = await _eventFor(schedule, [
          r.read<String>('expense_txn_id'),
          r.read<String>('source_txn_id'),
        ]);
        if (await _links.deleteById(linkId) != 1) _notFound();
        return ev;
      }),
    );
    _events?.publish(event);
    return event;
  }

  // ------------------------------------------------------------- EC-40

  /// Call inside the editing transaction, before writing [newAmountMinor]
  /// to [txnId] (an expense or an incoming transfer). Removes the newest
  /// links until the rest fits; the caller shows the notice when
  /// `removedLinkIds` is not empty. Does not publish: the edit's own event
  /// is published by the caller; `event` is there to be merged into it.
  Future<RepairResult> repairForNewAmount(
    String txnId,
    int newAmountMinor,
  ) async {
    if (txnId.isEmpty || newAmountMinor < 0) _invalid();
    final schedule = await _loadSchedule();
    return _guard(
      () => _txns.inTransaction(() async {
        final row = await _txns.byId(txnId);
        if (row == null) _notFound();
        final rows = await _db
            .customSelect(
              'SELECT id, amount_minor, created_at FROM offset_links '
              'WHERE expense_txn_id = ?1 OR source_txn_id = ?1',
              variables: [Variable.withString(txnId)],
              readsFrom: {_db.offsetLinks},
            )
            .get();
        final drop = linksToRemove(newAmountMinor, [
          for (final r in rows)
            LinkFact(
              id: r.read<String>('id'),
              amountMinor: r.read<int>('amount_minor'),
              createdAtMs: r.read<int>('created_at'),
            ),
        ]);
        TransactionsChanged? ev;
        if (drop.isNotEmpty) {
          ev = await _eventFor(schedule, [txnId]);
          for (final id in drop) {
            if (await _links.deleteById(id) != 1) _notFound();
          }
        }
        var shares = 0;
        for (final p in await _parts.forExpense(txnId)) {
          shares += p.shareMinor;
        }
        final result = RepairResult(
          removedLinkIds: drop,
          sharesExceedAmount: shares > newAmountMinor,
          event: ev,
        );
        return result;
      }),
    );
  }

  // ------------------------------------------------------------ helpers

  Future<TransactionRow> _expense(String id) async {
    final e = await _txns.byId(id);
    if (e == null) _notFound();
    if (e.deletedAt != null || e.direction != 'expense' || e.isInternal != 0) {
      throw ReimbursementException(ReimbursementException.notEligible);
    }
    return e;
  }

  Future<SplitParticipantRow> _participant(String id) async {
    final r = await (_db.select(
      _db.splitParticipants,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (r == null) _notFound();
    return r;
  }

  void _checkShares(TransactionRow e, List<int> shares) {
    final cur = Currency.of(e.currency);
    final problem = checkShares(Money(cur, e.amountMinor), [
      for (final s in shares) Money(cur, s),
    ]);
    if (problem == null) return;
    throw ReimbursementException(
      problem == ShareProblem.exceedsExpense
          ? ReimbursementException.sharesExceed
          : ReimbursementException.invalid,
    );
  }

  Future<int> _repaid(String participantId) async {
    final r = await _db
        .customSelect(
          'SELECT coalesce(sum(amount_minor), 0) AS s FROM offset_links '
          'WHERE participant_id = ?1',
          variables: [Variable.withString(participantId)],
          readsFrom: {_db.offsetLinks},
        )
        .getSingle();
    return r.read<int>('s');
  }

  Future<bool> _linkExists(String expenseId, String sourceId) async {
    final r = await _db
        .customSelect(
          'SELECT count(*) AS n FROM offset_links '
          'WHERE expense_txn_id = ?1 AND source_txn_id = ?2',
          variables: [
            Variable.withString(expenseId),
            Variable.withString(sourceId),
          ],
          readsFrom: {_db.offsetLinks},
        )
        .getSingle();
    return r.read<int>('n') > 0;
  }

  Future<void> _resolveSuggestion(String txnId, String how, int now) =>
      _db.customUpdate(
        'UPDATE review_items SET resolved_at = ?2, resolution = ?3 '
        'WHERE resolved_at IS NULL AND kind = ?4 AND txn_id = ?1',
        variables: [
          Variable.withString(txnId),
          Variable.withInt(now),
          Variable.withString(how),
          Variable.withString(ReviewKind.reimbursementSuggestion),
        ],
        updates: {_db.reviewItems},
      );

  Future<TransactionsChanged> _eventFor(
    PaydaySchedule schedule,
    Iterable<String> ids,
  ) async {
    final rows =
        <({String id, String accountId, int occurredAt, int offsetMin})>[];
    for (final id in ids.toSet()) {
      final t = await _txns.byId(id);
      if (t != null) {
        rows.add((
          id: t.id,
          accountId: t.accountId,
          occurredAt: t.occurredAt,
          offsetMin: t.occurredTzOffsetMin,
        ));
      }
    }
    return transactionsChangedFor(_db, schedule, rows);
  }

  /// A trigger or UNIQUE clash means another writer got there first (the
  /// transaction rolled back); any other failure is real.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DbWriteException catch (e) {
      if (e.code == DbWriteException.constraintUnique ||
          e.code.startsWith('OFFSET_')) {
        throw ReimbursementException(ReimbursementException.conflict);
      }
      rethrow;
    }
  }

  static String _name(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.runes.length > maxNameRunes) _invalid();
    return t;
  }

  static Never _invalid() =>
      throw ReimbursementException(ReimbursementException.invalid);
  static Never _notFound() =>
      throw ReimbursementException(ReimbursementException.notFound);
}
