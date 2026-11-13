// T-090: matches a refund to the expense it returns and records an offset
// link so net spend falls (BR-XFR-03, BR-TXN-01, EC-17; domain-algorithms
// §5). The deciding rules are `decideRefund` in `zaghlol_domain`.
//
// Safety rules (the money never doubles and never disappears):
// - Every call is one database transaction. The schema's triggers cap the
//   links of an expense at its amount and of a source at its amount, so a
//   racing caller can at worst lose (`skipped`), never over-offset.
// - The linked amount is `min(refund, remaining of the expense)`; the rest
//   of an oversized refund is not linked, so it still counts as income.
//   Nothing is converted: same currency only.
// - Doubt never links: equally recent originals open a review item, and a
//   refund the user unlinked is never auto-linked again.
// - A refund that already has a link is left alone (idempotent).
// - Removing a refund or an expense frees its links in the same
//   transaction (FU-127) and the cycles of both sides are announced
//   (FU-110). Deleting an expense lets its refunds look for another
//   original.
//
// Failures are code-only; nothing here logs and no payload carries amounts.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/offset_links_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/db_errors.dart';
import '../data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import 'transactions_changed_event.dart';

/// `OFFSET_NOT_FOUND`: the link is missing (already removed).
final class RefundMatchingException extends SafeException {
  RefundMatchingException(super.code);

  static const String notFound = 'OFFSET_NOT_FOUND';
  static const String invalid = 'OFFSET_INVALID';
}

enum RefundMatchStatus {
  /// Linked to one expense (an oversized remainder stays income).
  linked,

  /// Equally good originals: a review item is open, nothing linked.
  ambiguous,

  /// No original found: the refund counts as income.
  unmatched,

  /// Not a live posted refund, already linked, unlinked by the user, or
  /// another actor got there first. Nothing changed.
  skipped,
}

final class RefundMatchResult {
  const RefundMatchResult(
    this.status, {
    this.linkId,
    this.expenseId,
    this.linkedMinor,
    this.incomeRemainderMinor,
    this.event,
  });

  final RefundMatchStatus status;
  final String? linkId;
  final String? expenseId;
  final int? linkedMinor;
  final int? incomeRemainderMinor;
  final TransactionsChanged? event;
}

/// What [RefundMatching.onRemoved] did.
final class RemovalResult {
  const RemovalResult(this.event, this.rematched);

  /// Cycles and accounts of the removed row and every row it was linked to.
  final TransactionsChanged event;

  /// Refunds freed by removing their expense that found another original.
  final List<RefundMatchResult> rematched;
}

class RefundMatching {
  RefundMatching(
    this._db, {
    required this._loadSchedule,
    Clock? clock,
    IdGenerator? newId,
    this._events,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4,
       _txns = TransactionsDao(_db),
       _links = OffsetLinksDao(_db),
       _reviews = ReviewItemsDao(_db);

  final AppDatabase _db;
  final Future<PaydaySchedule> Function() _loadSchedule;
  final Clock _now;
  final IdGenerator _newId;
  final DomainEventBus? _events;
  final TransactionsDao _txns;
  final OffsetLinksDao _links;
  final ReviewItemsDao _reviews;

  static const int _poolLimit = 100;
  static const String _unlinked = 'unlinked';
  static const String _refundAmbiguous = 'refund_ambiguous';

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Run after a refund is stored or edited. Idempotent.
  Future<RefundMatchResult> onPersisted(String refundId) async {
    if (refundId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    RefundMatchResult result;
    try {
      result = await _txns.inTransaction(
        () => _evaluate(refundId, schedule, now),
      );
    } on DbWriteException catch (e) {
      // A trigger or UNIQUE clash means another actor linked first
      // (rolled back); any other failure is real.
      if (e.code != DbWriteException.constraintUnique &&
          !e.code.startsWith('OFFSET_')) {
        rethrow;
      }
      return const RefundMatchResult(RefundMatchStatus.skipped);
    }
    final ev = result.event;
    if (ev != null) _events?.publish(ev);
    return result;
  }

  /// Removes link [linkId] by hand (a wrong match). The refund is never
  /// auto-linked again. Returns the event for both sides' cycles.
  Future<TransactionsChanged> unlink(String linkId) async {
    if (linkId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final now = _nowMs();
    final event = await _txns.inTransaction(() async {
      final rows = await _db
          .customSelect(
            'SELECT expense_txn_id, source_txn_id FROM offset_links '
            'WHERE id = ?1',
            variables: [Variable.withString(linkId)],
            readsFrom: {_db.offsetLinks},
          )
          .get();
      if (rows.isEmpty) {
        throw RefundMatchingException(RefundMatchingException.notFound);
      }
      final expense = rows.single.read<String>('expense_txn_id');
      final source = rows.single.read<String>('source_txn_id');
      final event = await _eventFor(schedule, [expense, source]);
      if (await _links.deleteById(linkId) != 1) {
        throw RefundMatchingException(RefundMatchingException.notFound);
      }
      await _rememberUnlink(source, expense, now);
      return event;
    });
    _events?.publish(event);
    return event;
  }

  /// Run after a transaction is deleted (soft or hard; call before a hard
  /// purge, whose cascade would drop the links unseen). Frees every link of
  /// [txnId] on either side and lets refunds whose expense went away look
  /// for another original. Returns null when it had no link.
  Future<RemovalResult?> onRemoved(String txnId) async {
    if (txnId.isEmpty) _invalid();
    final schedule = await _loadSchedule();
    final freed = <String>[];
    final event = await _txns.inTransaction(() async {
      final rows = await _db
          .customSelect(
            'SELECT expense_txn_id, source_txn_id FROM offset_links '
            'WHERE expense_txn_id = ?1 OR source_txn_id = ?1',
            variables: [Variable.withString(txnId)],
            readsFrom: {_db.offsetLinks},
          )
          .get();
      if (rows.isEmpty) return null;
      final ids = <String>{txnId};
      for (final r in rows) {
        ids
          ..add(r.read<String>('expense_txn_id'))
          ..add(r.read<String>('source_txn_id'));
        if (r.read<String>('expense_txn_id') == txnId) {
          freed.add(r.read<String>('source_txn_id'));
        }
      }
      final event = await _eventFor(schedule, ids);
      await _db.customUpdate(
        'DELETE FROM offset_links WHERE expense_txn_id = ?1 '
        'OR source_txn_id = ?1',
        variables: [Variable.withString(txnId)],
        updates: {_db.offsetLinks},
      );
      await _db.customUpdate(
        'UPDATE review_items SET resolved_at = ?2, resolution = ?3 '
        'WHERE resolved_at IS NULL AND kind = ?4 AND txn_id = ?1',
        variables: [
          Variable.withString(txnId),
          Variable.withInt(_nowMs()),
          Variable.withString('removed'),
          Variable.withString(ReviewKind.reimbursementSuggestion),
        ],
        updates: {_db.reviewItems},
      );
      return event;
    });
    if (event == null) return null;
    _events?.publish(event);
    final again = <RefundMatchResult>[];
    for (final id in freed.toSet()) {
      again.add(await onPersisted(id));
    }
    return RemovalResult(event, again);
  }

  // ---------------------------------------------------------------- core

  Future<RefundMatchResult> _evaluate(
    String id,
    PaydaySchedule schedule,
    int now,
  ) async {
    const skipped = RefundMatchResult(RefundMatchStatus.skipped);
    final row = await _txns.byId(id);
    if (row == null ||
        row.deletedAt != null ||
        row.direction != 'refund' ||
        row.status != 'posted' ||
        row.isInternal != 0 ||
        row.amountMinor <= 0) {
      return skipped;
    }
    if (await _links.linkedFromSource(id) > 0 || await _wasUnlinked(id)) {
      return skipped;
    }
    final refund = RefundFact(
      id: id,
      accountId: row.accountId,
      merchantNorm: row.merchantNorm,
      amount: Money(Currency.of(row.currency), row.amountMinor),
      occurredAtMs: row.occurredAt,
      offsetMin: row.occurredTzOffsetMin,
    );
    final merchant = row.merchantNorm;
    if (merchant == null || merchant.isEmpty) {
      return const RefundMatchResult(RefundMatchStatus.unmatched);
    }
    final day = 86400000;
    final pool = await _db
        .customSelect(
          'SELECT t.id, t.account_id, t.merchant_norm, t.occurred_at, '
          't.occurred_tz_offset_min, '
          't.amount_minor - coalesce((SELECT sum(l.amount_minor) '
          'FROM offset_links l WHERE l.expense_txn_id = t.id), 0) AS rem '
          'FROM transactions t '
          'WHERE t.deleted_at IS NULL AND t.direction = \'expense\' '
          "AND t.status IN ('posted','pending') AND t.is_internal = 0 "
          'AND t.currency = ?1 AND t.account_id = ?2 '
          'AND t.merchant_norm = ?3 AND t.id <> ?4 '
          'AND t.occurred_at BETWEEN ?5 AND ?6 '
          'AND rem > 0 ORDER BY t.occurred_at DESC, t.id LIMIT ?7',
          variables: [
            Variable.withString(row.currency),
            Variable.withString(row.accountId),
            Variable.withString(merchant),
            Variable.withString(id),
            // Generous bounds; the exact 60 local days are in the domain.
            Variable.withInt(row.occurredAt - 62 * day),
            Variable.withInt(row.occurredAt + 2 * day),
            Variable.withInt(_poolLimit),
          ],
          readsFrom: {_db.transactions, _db.offsetLinks},
        )
        .get();
    final cur = refund.amount.currency;
    final decision = decideRefund(refund, [
      for (final r in pool)
        OffsetCandidate(
          id: r.read<String>('id'),
          accountId: r.read<String>('account_id'),
          merchantNorm: r.read<String?>('merchant_norm'),
          remaining: Money(cur, r.read<int>('rem')),
          occurredAtMs: r.read<int>('occurred_at'),
          offsetMin: r.read<int>('occurred_tz_offset_min'),
        ),
    ]);
    switch (decision) {
      case NoRefundMatch():
        return const RefundMatchResult(RefundMatchStatus.unmatched);
      case AmbiguousRefund(:final candidateIds):
        await _openReview(id, candidateIds, now);
        return const RefundMatchResult(RefundMatchStatus.ambiguous);
      case LinkRefund(:final expenseId, :final linked, :final incomeRemainder):
        final linkId = _newId();
        await _links.insert(
          OffsetLinksCompanion.insert(
            id: linkId,
            kind: 'refund',
            expenseTxnId: expenseId,
            sourceTxnId: id,
            amountMinor: linked.minor,
            createdAt: now,
          ),
        );
        await _db.customUpdate(
          'UPDATE review_items SET resolved_at = ?2, resolution = ?3 '
          'WHERE resolved_at IS NULL AND kind = ?4 AND txn_id = ?1',
          variables: [
            Variable.withString(id),
            Variable.withInt(now),
            Variable.withString('linked'),
            Variable.withString(ReviewKind.reimbursementSuggestion),
          ],
          updates: {_db.reviewItems},
        );
        return RefundMatchResult(
          RefundMatchStatus.linked,
          linkId: linkId,
          expenseId: expenseId,
          linkedMinor: linked.minor,
          incomeRemainderMinor: incomeRemainder.minor,
          event: await _eventFor(schedule, [id, expenseId]),
        );
    }
  }

  Future<TransactionsChanged> _eventFor(
    PaydaySchedule schedule,
    Iterable<String> ids,
  ) async {
    final rows =
        <({String id, String accountId, int occurredAt, int offsetMin})>[];
    for (final id in ids) {
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

  Future<void> _openReview(String id, List<String> candidates, int now) async {
    final open = await _db
        .customSelect(
          'SELECT count(*) AS n FROM review_items WHERE kind = ?1 '
          'AND resolved_at IS NULL AND txn_id = ?2',
          variables: [
            Variable.withString(ReviewKind.reimbursementSuggestion),
            Variable.withString(id),
          ],
          readsFrom: {_db.reviewItems},
        )
        .getSingle();
    if (open.read<int>('n') > 0) return;
    await _reviews.insert(
      id: _newId(),
      kind: ReviewKind.reimbursementSuggestion,
      txnId: id,
      payload: {'type': _refundAmbiguous, 'candidates': candidates},
      createdAt: now,
    );
  }

  Future<void> _rememberUnlink(String source, String expense, int now) async {
    final itemId = _newId();
    await _reviews.insert(
      id: itemId,
      kind: ReviewKind.reimbursementSuggestion,
      txnId: source,
      payload: {
        'type': _unlinked,
        'candidates': [expense],
      },
      createdAt: now,
    );
    await _reviews.resolve(itemId, resolution: _unlinked, at: now);
  }

  Future<bool> _wasUnlinked(String id) async {
    final r = await _db
        .customSelect(
          'SELECT count(*) AS n FROM review_items WHERE kind = ?1 '
          'AND resolution = ?2 AND txn_id = ?3',
          variables: [
            Variable.withString(ReviewKind.reimbursementSuggestion),
            Variable.withString(_unlinked),
            Variable.withString(id),
          ],
          readsFrom: {_db.reviewItems},
        )
        .getSingle();
    return r.read<int>('n') > 0;
  }

  static Never _invalid() =>
      throw RefundMatchingException(RefundMatchingException.invalid);
}
