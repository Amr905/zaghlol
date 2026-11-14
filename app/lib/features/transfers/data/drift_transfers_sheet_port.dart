// T-093: Drift-backed implementation of the sheets' port. Reads go through
// the transaction repository and the offset/participant DAOs; writes go
// through `Reimbursements` (T-091) and `TransferPairingUseCase` (T-089),
// which hold every safety rule. Nothing here logs; failures are codes only.

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/offset_links_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transfers_dao.dart';
import '../../transactions/application/reimbursements.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_repository.dart';
import '../presentation/transfers_port.dart';

class DriftTransfersSheetPort implements TransfersSheetPort {
  DriftTransfersSheetPort({
    required this._db,
    required this._repo,
    required this._reimbursements,
    required this._pairing,
    required this._accountLabel,
    required this._now,
  });

  final AppDatabase _db;
  final TransactionRepository _repo;
  final Reimbursements _reimbursements;
  final TransferPairingUseCase _pairing;
  final String Function(String accountId) _accountLabel;
  final DateTime Function() _now;

  static const int assignWindowDays = 60;
  static const int linkWindowDays = 7;
  static const int maxCandidates = 100;

  static DateTime _local(TransactionRecord t) =>
      t.occurredAt.add(Duration(minutes: t.occurredTzOffsetMin));

  static String _who(TransactionRecord t) =>
      t.merchantNorm ?? t.merchantRaw ?? '';

  static bool _isExpense(TransactionRecord t) =>
      t.direction == TxnDirection.expense &&
      !t.isInternal &&
      t.status == TxnStatus.posted;

  // ------------------------------------------------------------- Mode A

  @override
  Future<SplitData?> loadSplit(String expenseId) async {
    final e = await _repo.byId(expenseId);
    if (e == null || !_isExpense(e)) return null;
    final cur = e.amount.currency;
    final links = await OffsetLinksDao(_db).forExpense(expenseId);
    final people = <SplitPerson>[];
    for (final p in await SplitParticipantsDao(_db).forExpense(expenseId)) {
      final repayments = <SplitRepayment>[];
      for (final l in links) {
        if (l.participantId != p.id || l.kind != 'reimbursement') continue;
        final src = await _repo.byId(l.sourceTxnId);
        repayments.add(
          SplitRepayment(
            linkId: l.id,
            sourceId: l.sourceTxnId,
            amount: Money(cur, l.amountMinor),
            sourceLabel: src == null ? '' : _accountLabel(src.accountId),
            date: src == null ? _now() : _local(src),
          ),
        );
      }
      people.add(
        SplitPerson(
          id: p.id,
          name: p.name,
          share: Money(cur, p.shareMinor),
          repayments: repayments,
        ),
      );
    }
    return SplitData(
      expenseId: expenseId,
      merchant: _who(e),
      amount: e.amount,
      people: people,
      suggestions: await _suggestions(e, people),
    );
  }

  /// Open reimbursement suggestions that name this expense (FR-XFR-08).
  Future<List<SplitSuggestion>> _suggestions(
    TransactionRecord e,
    List<SplitPerson> people,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT txn_id, payload FROM review_items WHERE kind = ?1 '
          'AND resolved_at IS NULL AND instr(payload, ?2) > 0',
          variables: [
            Variable.withString(ReviewKind.reimbursementSuggestion),
            Variable.withString(e.id),
          ],
          readsFrom: {_db.reviewItems},
        )
        .get();
    final out = <SplitSuggestion>[];
    for (final r in rows) {
      final raw = r.read<String?>('payload');
      if (raw == null) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      if (decoded is! Map || decoded['type'] == 'unlinked') continue;
      final cands = decoded['candidates'];
      if (cands is! List || !cands.contains(e.id)) continue;
      final src = await _repo.byId(r.read<String>('txn_id'));
      if (src == null ||
          src.amount.currency != e.amount.currency ||
          (src.direction != TxnDirection.income &&
              src.direction != TxnDirection.transferIn)) {
        continue;
      }
      final who = _who(src);
      String? pid;
      for (final p in people) {
        if (p.name.trim().toLowerCase() == who.trim().toLowerCase()) {
          pid = p.id;
        }
      }
      out.add(
        SplitSuggestion(
          sourceId: src.id,
          person: who,
          amount: src.amount,
          date: _local(src),
          participantId: pid,
        ),
      );
    }
    return out;
  }

  @override
  Future<void> saveSplit(
    String expenseId,
    List<SplitEdit> edits,
    Set<String> removedIds,
  ) async {
    // Shrinks and removals first so the sum cap never trips mid-way.
    for (final id in removedIds) {
      await _reimbursements.removeParticipant(id);
    }
    final current = {
      for (final p in await SplitParticipantsDao(_db).forExpense(expenseId))
        p.id: p.shareMinor,
    };
    final changes =
        [
          for (final e in edits)
            if (e.id != null && current[e.id] != e.shareMinor) e,
        ]..sort(
          (a, b) => (a.shareMinor - current[a.id]!).compareTo(
            b.shareMinor - current[b.id]!,
          ),
        );
    for (final e in changes) {
      await _reimbursements.updateShare(e.id!, e.shareMinor);
    }
    for (final e in edits) {
      if (e.id == null) {
        await _reimbursements.addParticipant(expenseId, e.name, e.shareMinor);
      }
    }
  }

  // ------------------------------------------------------------- Mode B

  @override
  Future<AssignData?> loadAssign(
    String sourceId, {
    bool searchAll = false,
  }) async {
    final s = await _repo.byId(sourceId);
    if (s == null ||
        s.isInternal ||
        s.status != TxnStatus.posted ||
        (s.direction != TxnDirection.income &&
            s.direction != TxnDirection.transferIn)) {
      return null;
    }
    final cur = s.amount.currency;
    final links = OffsetLinksDao(_db);
    final left = s.amount.minor - await links.linkedFromSource(sourceId);
    final rows = await _repo.query(
      filter: TransactionFilter(
        from: searchAll
            ? null
            : _now().subtract(const Duration(days: assignWindowDays)),
        directions: const {TxnDirection.expense},
        currencies: {cur},
      ),
      page: const PageRequest(limit: maxCandidates),
    );
    final cands = <AssignCandidate>[];
    for (final e in rows) {
      if (!_isExpense(e)) continue;
      final room = e.amount.minor - await links.linkedToExpense(e.id);
      if (room <= 0) continue;
      cands.add(
        AssignCandidate(
          expenseId: e.id,
          merchant: _who(e),
          date: _local(e),
          amount: e.amount,
          room: Money(cur, room),
        ),
      );
    }
    return AssignData(
      sourceId: sourceId,
      person: _who(s),
      amount: s.amount,
      left: Money(cur, left < 0 ? 0 : left),
      candidates: cands,
      windowDays: assignWindowDays,
      searchedAll: searchAll,
    );
  }

  @override
  Future<Money> assign(
    String sourceId,
    List<AssignLine> lines, {
    String? participantId,
  }) async {
    final src = await _repo.byId(sourceId);
    final cur = src?.amount.currency;
    final result = await _reimbursements.assign(sourceId, [
      for (final l in lines)
        AssignRequest(
          expenseId: l.expenseId,
          amountMinor: l.amountMinor,
          participantId: participantId,
        ),
    ]);
    final granted = result.plan.grants.fold<int>(
      0,
      (s, g) => s + g.granted.minor,
    );
    if (cur == null) {
      throw ReimbursementException(ReimbursementException.notFound);
    }
    return Money(cur, granted);
  }

  @override
  Future<void> unassign(String linkId) async {
    await _reimbursements.unassign(linkId);
  }

  // ----------------------------------------------------------------- S-16

  @override
  Future<LinkData?> loadLink(String txnId) async {
    final s = await _repo.byId(txnId);
    if (s == null || s.status != TxnStatus.posted) return null;
    final isOut = switch (s.direction) {
      TxnDirection.expense ||
      TxnDirection.transferOut ||
      TxnDirection.fee => true,
      TxnDirection.income ||
      TxnDirection.transferIn ||
      TxnDirection.refund => false,
    };
    final wantOut = !isOut;
    final window = const Duration(days: linkWindowDays);
    final rows = await _repo.query(
      filter: TransactionFilter(
        from: s.occurredAt.subtract(window),
        to: s.occurredAt.add(window),
      ),
      page: const PageRequest(limit: maxCandidates),
    );
    final cands = <LinkCandidate>[];
    for (final c in rows) {
      final cOut = switch (c.direction) {
        TxnDirection.expense ||
        TxnDirection.transferOut ||
        TxnDirection.fee => true,
        _ => false,
      };
      if (c.id == s.id ||
          cOut != wantOut ||
          c.status != TxnStatus.posted ||
          c.accountId == s.accountId) {
        continue;
      }
      cands.add(
        LinkCandidate(
          id: c.id,
          amount: c.amount,
          accountLabel: _accountLabel(c.accountId),
          when: _local(c),
          gapMinutes: c.occurredAt.difference(s.occurredAt).inMinutes,
        ),
      );
    }
    int rank(LinkCandidate c) =>
        (c.amount == s.amount ? 0 : 1) * 100000000 + c.gapMinutes.abs();
    cands.sort((a, b) => rank(a).compareTo(rank(b)));
    return LinkData(
      id: s.id,
      amount: s.amount,
      accountLabel: _accountLabel(s.accountId),
      when: _local(s),
      isOut: isOut,
      candidates: cands,
    );
  }

  @override
  Future<void> link(String outId, String inId) async {
    await _pairing.link(outId, inId);
  }

  @override
  Future<void> unlink(String txnId) async {
    await _pairing.unlink(txnId);
  }

  // `TransferPairingUseCase` has no manual one-sided marker yet (EC-15):
  // open question in the task file. The sheet hides the action.
  @override
  bool get supportsMarkAnyway => false;

  @override
  Future<void> markAnyway(String txnId) async {
    throw UnsupportedError('markAnyway');
  }
}
