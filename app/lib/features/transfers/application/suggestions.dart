// T-092: one-tap pair suggestions (FR-XFR-08, FR-CUR-06; domain-algorithms
// §5). Suggestions are review items; nothing here writes a link or a pair
// unless the user taps accept, and accepting goes through the same use cases
// as the manual flow (`Reimbursements.assign`, `TransferPairingUseCase.link`).
//
// Safety rules:
// - Same currency only for reimbursements; nothing is converted. A
//   cross-currency pair is only ever linked by `acceptFxPair`, which the UI
//   calls from a tap, and the amounts stay as they are.
// - A suggestion names ids, never amounts or text (payloads are ids only).
// - Dismissing is remembered: the dismissed item stays (resolved) and lists
//   the candidates the user said no to; they are not suggested again.
//   For cross-currency pairs the memory is read by `TransferPairingUseCase`.
// - Failures are code-only; nothing here logs.

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/offset_links_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../transactions/application/reimbursements.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;

final class SuggestionException extends SafeException {
  SuggestionException(super.code);

  /// The item is missing, already resolved or of another kind.
  static const String notOpen = 'SUGG_NOT_OPEN';

  /// The chosen candidate is not one the suggestion named.
  static const String notCandidate = 'SUGG_NOT_CANDIDATE';
}

enum SuggestionStatus {
  /// A review item is open for the incoming transfer.
  opened,

  /// An item was already open; nothing added.
  alreadyOpen,

  /// Not an eligible incoming person-to-person transfer, or nothing fits.
  none,
}

final class SuggestionResult {
  const SuggestionResult(
    this.status, {
    this.itemId,
    this.expenseIds = const [],
  });

  final SuggestionStatus status;
  final String? itemId;

  /// Candidate expenses, most recent first (the best one is first).
  final List<String> expenseIds;
}

class PairSuggestions {
  PairSuggestions(
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

  /// A-45: how long after an expense a repayment is suggested.
  static const Duration window = Duration(days: 7);

  /// Most candidates named in one suggestion.
  static const int maxCandidates = 5;

  static const String typeP2p = 'p2p_reimbursement';
  static const String dismissed = 'dismissed';

  /// Categories whose expenses are usually shared (system codes; a
  /// sub-category counts through its parent).
  static const Set<String> sharedCategoryCodes = {
    'dining',
    'entertainment',
    'travel',
  };

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Run after an incoming transfer is stored. Opens a
  /// `reimbursement_suggestion` item when an eligible expense exists; never
  /// links anything. Idempotent.
  Future<SuggestionResult> suggestReimbursement(String incomingId) async {
    if (incomingId.isEmpty) {
      throw SuggestionException(SuggestionException.notOpen);
    }
    final now = _nowMs();
    return _txns.inTransaction(() async {
      const none = SuggestionResult(SuggestionStatus.none);
      final i = await _txns.byId(incomingId);
      if (i == null ||
          i.deletedAt != null ||
          i.status != 'posted' ||
          i.isInternal != 0 ||
          i.amountMinor <= 0 ||
          (i.direction != 'income' && i.direction != 'transfer_in') ||
          !const {'person', 'phone', 'ipa'}.contains(i.counterpartyKind)) {
        return none;
      }
      final open = await _db
          .customSelect(
            'SELECT id FROM review_items WHERE kind = ?1 '
            'AND resolved_at IS NULL AND txn_id = ?2 LIMIT 1',
            variables: [
              Variable.withString(ReviewKind.reimbursementSuggestion),
              Variable.withString(incomingId),
            ],
            readsFrom: {_db.reviewItems},
          )
          .get();
      if (open.isNotEmpty) {
        return SuggestionResult(
          SuggestionStatus.alreadyOpen,
          itemId: open.single.read<String>('id'),
        );
      }
      final left = i.amountMinor - await _links.linkedFromSource(incomingId);
      if (left <= 0) return none;
      final no = await _dismissedCandidates(incomingId);
      final rows = await _db
          .customSelect(
            'SELECT e.id, e.amount_minor FROM transactions e '
            'LEFT JOIN categories c ON c.id = e.category_id '
            'LEFT JOIN categories p ON p.id = c.parent_id '
            "WHERE e.deleted_at IS NULL AND e.direction = 'expense' "
            "AND e.status = 'posted' AND e.is_internal = 0 "
            'AND e.currency = ?1 AND e.id <> ?2 '
            'AND e.occurred_at BETWEEN ?3 AND ?4 '
            'AND (c.system_code IN (?5, ?6, ?7) OR p.system_code IN (?5, ?6, ?7) '
            'OR EXISTS (SELECT 1 FROM split_participants s '
            'WHERE s.expense_txn_id = e.id)) '
            'AND NOT EXISTS (SELECT 1 FROM offset_links l '
            'WHERE l.expense_txn_id = e.id AND l.source_txn_id = ?2) '
            'ORDER BY e.occurred_at DESC, e.id LIMIT 50',
            variables: [
              Variable.withString(i.currency),
              Variable.withString(incomingId),
              Variable.withInt(i.occurredAt - window.inMilliseconds),
              Variable.withInt(i.occurredAt),
              for (final code in sharedCategoryCodes.toList()..sort())
                Variable.withString(code),
            ],
            readsFrom: {_db.transactions, _db.categories, _db.offsetLinks},
          )
          .get();
      final ids = <String>[];
      for (final r in rows) {
        final id = r.read<String>('id');
        if (no.contains(id)) continue;
        final remaining =
            r.read<int>('amount_minor') - await _links.linkedToExpense(id);
        if (remaining >= left) ids.add(id);
        if (ids.length == maxCandidates) break;
      }
      if (ids.isEmpty) return none;
      final itemId = _newId();
      await _reviews.insert(
        id: itemId,
        kind: ReviewKind.reimbursementSuggestion,
        txnId: incomingId,
        payload: {'type': typeP2p, 'candidates': ids},
        createdAt: now,
      );
      return SuggestionResult(
        SuggestionStatus.opened,
        itemId: itemId,
        expenseIds: ids,
      );
    });
  }

  /// The user tapped "yes, this is from that bill": puts the incoming
  /// transfer (what it has left, never more than the expense has room for)
  /// on [expenseId]. The item resolves as `linked` inside the assignment.
  Future<AssignResult> acceptReimbursement(
    String itemId,
    String expenseId,
  ) async {
    final item = await _openItem(itemId, ReviewKind.reimbursementSuggestion);
    final payload = reviewPayloadOf(item);
    if (payload?['type'] != typeP2p) {
      throw SuggestionException(SuggestionException.notOpen);
    }
    _requireCandidate(payload, expenseId);
    final incomingId = item.txnId;
    final i = incomingId == null ? null : await _txns.byId(incomingId);
    if (i == null) throw SuggestionException(SuggestionException.notOpen);
    final left = i.amountMinor - await _links.linkedFromSource(i.id);
    if (left <= 0) throw SuggestionException(SuggestionException.notOpen);
    final uc = Reimbursements(
      _db,
      loadSchedule: _loadSchedule,
      clock: _now,
      newId: _newId,
      events: _events,
    );
    return uc.assign(i.id, [
      AssignRequest(expenseId: expenseId, amountMinor: left),
    ]);
  }

  /// The user tapped "yes, these are one transfer": pairs the two legs of a
  /// cross-currency `fx_pair_suggestion` (FR-CUR-06). No amount is changed.
  Future<PairingResult> acceptFxPair(String itemId, String candidateId) async {
    final item = await _openItem(itemId, ReviewKind.fxPairSuggestion);
    _requireCandidate(reviewPayloadOf(item), candidateId);
    final selfId = item.txnId;
    final a = selfId == null ? null : await _txns.byId(selfId);
    final b = await _txns.byId(candidateId);
    if (a == null || b == null) {
      throw SuggestionException(SuggestionException.notOpen);
    }
    final aOut = a.direction == 'transfer_out';
    final uc = TransferPairingUseCase(
      _db,
      loadSchedule: _loadSchedule,
      clock: _now,
      newId: _newId,
      events: _events,
    );
    final r = await (aOut ? uc.link(a.id, b.id) : uc.link(b.id, a.id));
    // `link` resolves items on both legs; this one is resolved either way.
    await _reviews.resolve(itemId, resolution: 'linked', at: _nowMs());
    return r;
  }

  /// The user said no. Remembered: the candidates are not suggested again.
  /// Returns false when the item was already resolved.
  Future<bool> dismiss(String itemId) async {
    final row = await _reviews.byId(itemId);
    if (row == null ||
        (row.kind != ReviewKind.reimbursementSuggestion &&
            row.kind != ReviewKind.fxPairSuggestion)) {
      throw SuggestionException(SuggestionException.notOpen);
    }
    return _reviews.resolve(itemId, resolution: dismissed, at: _nowMs());
  }

  Future<ReviewItemRow> _openItem(String id, String kind) async {
    final row = await _reviews.byId(id);
    if (row == null || row.kind != kind || row.resolvedAt != null) {
      throw SuggestionException(SuggestionException.notOpen);
    }
    return row;
  }

  static void _requireCandidate(Map<String, Object?>? payload, String id) {
    final c = payload?['candidates'];
    if (c is! List || !c.contains(id)) {
      throw SuggestionException(SuggestionException.notCandidate);
    }
  }

  Future<Set<String>> _dismissedCandidates(String txnId) async {
    final rows = await _db
        .customSelect(
          'SELECT payload FROM review_items WHERE kind = ?1 '
          'AND resolution = ?2 AND txn_id = ?3',
          variables: [
            Variable.withString(ReviewKind.reimbursementSuggestion),
            Variable.withString(dismissed),
            Variable.withString(txnId),
          ],
          readsFrom: {_db.reviewItems},
        )
        .get();
    final out = <String>{};
    for (final r in rows) {
      final raw = r.read<String?>('payload');
      if (raw == null) continue;
      final c = (jsonDecode(raw) as Map)['candidates'];
      if (c is List) out.addAll(c.whereType<String>());
    }
    return out;
  }
}
