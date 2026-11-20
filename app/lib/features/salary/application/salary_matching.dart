// T-195 (D-71): ties a received salary to the expected or hand-entered one,
// so the salary is counted exactly once. The deciding rules are in
// `zaghlol_domain` (`decideSalaryCandidate`); this file reads and writes.
//
// Safety rules:
// - Every call is one database transaction on the caller's connection, so
//   the UI engine and the background engine serialise. The merge soft-deletes
//   the manual row with a conditional update (`deleted_at IS NULL`); if it is
//   already gone nothing is merged and the credit stays a plain income.
// - Totals only ever read `transactions`. The expected salary is not a row,
//   and a merge leaves exactly one live row (the captured one), so income is
//   neither lost nor doubled.
// - Nothing is converted: the currency must be the same. Doubt (two manual
//   entries or no clear match) never merges.
// - The captured credit is never edited beyond a category it did not have
//   and a note it did not have; its amount, time and message stay as read.
//
// Failures are code-only; nothing here logs and no payload carries amounts.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../transactions/application/transactions_changed_event.dart';
import '../../transactions/data/drift_transaction_repository.dart' show Clock;

/// Why [SalaryMatching.undoMerge] did nothing.
final class SalaryException extends SafeException {
  SalaryException(super.code);

  /// No merge is recorded for that transaction.
  static const String noMerge = 'SALARY_NO_MERGE';

  /// The replaced manual row was purged (30 days) or is gone.
  static const String gone = 'SALARY_GONE';
}

/// What one call did.
enum SalaryMatchStatus {
  /// Tied to the expected payday; nothing else changed.
  tagged,

  /// Replaced a manual salary; one live row remains.
  merged,

  /// Not a salary, no match, doubt, or another actor got there first.
  none,
}

class SalaryMatching {
  SalaryMatching(
    this._db, {
    required this._loadSchedule,
    Clock? clock,
    this._events,
  }) : _now = clock ?? DateTime.now,
       _txns = TransactionsDao(_db),
       _settings = SettingsRepository(
         SettingsDao(_db),
         nowMs: () => (clock ?? DateTime.now)().toUtc().millisecondsSinceEpoch,
       );

  final AppDatabase _db;
  final Future<PaydaySchedule> Function() _loadSchedule;
  final Clock _now;
  final DomainEventBus? _events;
  final TransactionsDao _txns;
  final SettingsRepository _settings;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Run after a credit is stored (the ingest hook) or on [reconcile].
  /// Idempotent.
  Future<SalaryMatchStatus> onPersisted(String txnId) async {
    if (txnId.isEmpty) return SalaryMatchStatus.none;
    final schedule = await _loadSchedule();
    final out = await _txns.inTransaction(() => _evaluate(txnId, schedule));
    if (out.event != null) _events?.publish(out.event!);
    return out.status;
  }

  /// Ties credits that arrived while no plan was set (or when the hook
  /// failed) to the payday they belong to. Looks at the credits of the last
  /// [lookbackDays] days only.
  Future<int> reconcile({
    required CivilDate today,
    int lookbackDays = 40,
  }) async {
    final plan = await _settings.get(Settings.salaryPlan);
    final state = await _settings.get(Settings.salaryState);
    if (plan == null && !state.entries.any((e) => !e.captured)) return 0;
    final from =
        today.plusDays(-lookbackDays).epochDay * 86400000 - 14 * 3600000;
    final rows = await _db
        .customSelect(
          'SELECT id FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'posted' AND is_internal = 0 "
          "AND source <> 'manual' AND direction IN ('income', 'transfer_in') "
          'AND occurred_at >= ?1 ORDER BY occurred_at',
          variables: [Variable.withInt(from)],
          readsFrom: {_db.transactions},
        )
        .get();
    var n = 0;
    for (final r in rows) {
      final s = await onPersisted(r.read<String>('id'));
      if (s != SalaryMatchStatus.none) n++;
    }
    return n;
  }

  /// Undo of a merge: restores the manual row, forgets the link and never
  /// merges [capturedTxnId] again. Both rows count as income afterwards (the
  /// user said they are two payments).
  Future<void> undoMerge(String capturedTxnId) async {
    final schedule = await _loadSchedule();
    final event = await _txns.inTransaction(() async {
      final state = await _settings.get(Settings.salaryState);
      final entry = state.entryOf(capturedTxnId);
      final manualId = entry?.mergedTxnId;
      if (entry == null || manualId == null) {
        throw SalaryException(SalaryException.noMerge);
      }
      if (await _txns.restore(manualId, at: _nowMs()) != 1) {
        throw SalaryException(SalaryException.gone);
      }
      await _settings.set(
        Settings.salaryState,
        state
            .withEntry(entry.withoutMerged())
            .withEntry(
              SalaryEntry(
                txnId: manualId,
                captured: false,
                anchor: entry.anchor,
              ),
            )
            .withDeclined(capturedTxnId),
      );
      return _eventFor(schedule, [capturedTxnId, manualId]);
    });
    _events?.publish(event);
  }

  // ------------------------------------------------------------- core

  Future<({SalaryMatchStatus status, TransactionsChanged? event})> _evaluate(
    String id,
    PaydaySchedule schedule,
  ) async {
    const none = (status: SalaryMatchStatus.none, event: null);
    final row = await _txns.byId(id);
    if (row == null ||
        row.deletedAt != null ||
        row.status != 'posted' ||
        row.isInternal != 0 ||
        row.transferPairId != null ||
        row.source == 'manual' ||
        row.amountMinor <= 0 ||
        (row.direction != 'income' && row.direction != 'transfer_in')) {
      return none;
    }
    final plan = await _settings.get(Settings.salaryPlan);
    final state = await _settings.get(Settings.salaryState);
    if (plan == null && !state.entries.any((e) => !e.captured)) return none;
    final amount = Money.tryFromStorage(row.amountMinor, row.currency);
    if (amount == null) return none;
    final credit = SalaryCandidate(
      amount: amount,
      localDate: CivilDate.fromLocalMs(row.occurredAt, row.occurredTzOffsetMin),
      keyword: salaryLooksLikeSalary([
        row.merchantRaw,
        row.counterpartyValue,
        row.note,
      ]),
    );
    final live = await _liveEntries(state);
    final manualTxns = [
      for (final e in state.entries)
        if (!e.captured && live[e.txnId] != null)
          LiveSalaryTxn(e.txnId, live[e.txnId]!),
    ];
    final decision = decideSalaryCandidate(
      creditTxnId: id,
      credit: credit,
      plan: plan,
      state: state,
      liveManual: [
        for (final e in state.entries)
          if (!e.captured && live.containsKey(e.txnId)) e,
      ],
      liveManualTxns: manualTxns,
      paydayClosed: (p) =>
          state.entries.any((e) => e.anchor == p && live.containsKey(e.txnId)),
    );
    switch (decision) {
      case SalaryNone():
        return none;
      case SalaryTagExpected(:final payday):
        await _giveIncomeCategory(id);
        await _settings.set(
          Settings.salaryState,
          state.withEntry(
            SalaryEntry(txnId: id, captured: true, anchor: payday),
          ),
        );
        return (
          status: SalaryMatchStatus.tagged,
          event: await _eventFor(schedule, [id]),
        );
      case SalaryMergeManual(:final entry):
        final manualAmount = live[entry.txnId]!;
        // The conditional soft delete is the "exactly one winner" step.
        if (await _txns.softDelete(entry.txnId, at: _nowMs()) != 1) {
          return none;
        }
        await _copyNote(from: entry.txnId, to: id);
        await _giveIncomeCategory(id);
        await _settings.set(
          Settings.salaryState,
          state
              .withoutEntry(entry.txnId)
              .withEntry(
                SalaryEntry(
                  txnId: id,
                  captured: true,
                  anchor: entry.anchor,
                ).withMerged(entry.txnId, manualAmount),
              ),
        );
        return (
          status: SalaryMatchStatus.merged,
          event: await _eventFor(schedule, [id, entry.txnId]),
        );
    }
  }

  /// The live (not deleted, posted) entries of [state] with their amounts.
  Future<Map<String, Money>> _liveEntries(SalaryState state) async {
    final out = <String, Money>{};
    for (final e in state.entries) {
      final r = await _db
          .customSelect(
            'SELECT amount_minor, currency FROM transactions '
            "WHERE id = ?1 AND deleted_at IS NULL AND status = 'posted' "
            "AND direction IN ('income', 'transfer_in') AND is_internal = 0",
            variables: [Variable.withString(e.txnId)],
            readsFrom: {_db.transactions},
          )
          .getSingleOrNull();
      if (r == null) continue;
      final m = Money.tryFromStorage(
        r.read<int>('amount_minor'),
        r.read<String>('currency'),
      );
      if (m != null) out[e.txnId] = m;
    }
    return out;
  }

  /// Tags the credit as income when it has no category (the seeded
  /// `sys:income`; a category the user or a rule chose is kept).
  Future<void> _giveIncomeCategory(String id) => _db.customUpdate(
    "UPDATE transactions SET category_id = 'sys:income', "
    "category_source = 'heuristic', updated_at = ?2 "
    'WHERE id = ?1 AND category_id IS NULL '
    "AND EXISTS (SELECT 1 FROM categories WHERE id = 'sys:income')",
    variables: [Variable.withString(id), Variable.withInt(_nowMs())],
    updates: {_db.transactions},
  );

  Future<void> _copyNote({required String from, required String to}) =>
      _db.customUpdate(
        'UPDATE transactions SET note = '
        '(SELECT note FROM transactions WHERE id = ?1) '
        'WHERE id = ?2 AND note IS NULL',
        variables: [Variable.withString(from), Variable.withString(to)],
        updates: {_db.transactions},
      );

  Future<TransactionsChanged> _eventFor(
    PaydaySchedule schedule,
    Iterable<String> ids,
  ) async {
    final rows =
        <({String id, String accountId, int occurredAt, int offsetMin})>[];
    for (final id in ids) {
      final r = await _txns.byId(id);
      if (r == null) continue;
      rows.add((
        id: r.id,
        accountId: r.accountId,
        occurredAt: r.occurredAt,
        offsetMin: r.occurredTzOffsetMin,
      ));
    }
    return transactionsChangedFor(_db, schedule, rows);
  }
}
