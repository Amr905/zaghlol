// T-195 (D-71): what the screens do about the salary: set "My salary",
// see the expected item, confirm it ("it arrived"), skip it, add a salary by
// hand, tie an existing credit to it. Matching of received messages is
// `SalaryMatching`; the deciding rules are in `zaghlol_domain`.
//
// Safety rules:
// - The expected item is derived (plan + today + state), never a row, so it
//   is in no total until a real transaction exists.
// - Recording by hand first looks for a received credit that already matches
//   (same currency, window, amount or keyword). Found: nothing is written
//   and the caller asks the user; the answer is `linkExisting` (same one) or
//   `allowDuplicate: true` (another income).
// - The manual row and its state entry are written in one transaction.
//
// Failures are code-only; nothing here logs and no payload carries amounts.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../ingestion/domain/ingest_ports.dart' show LocalZone;
import '../../transactions/data/drift_transaction_repository.dart' show Clock;
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_repository.dart';

/// `SALARY_NO_PLAN`: no salary plan is set. `SALARY_NO_ACCOUNT`: neither the
/// plan's account nor a default cash account exists. `SALARY_NOT_OPEN`: the
/// payday is already closed (tied, skipped) or not open now.
final class SalaryServiceException extends SafeException {
  SalaryServiceException(super.code);

  static const String noPlan = 'SALARY_NO_PLAN';
  static const String noAccount = 'SALARY_NO_ACCOUNT';
  static const String notOpen = 'SALARY_NOT_OPEN';
}

/// The expected salary Home shows.
final class ExpectedSalary {
  const ExpectedSalary(this.payday, this.amount, this.accountId);
  final CivilDate payday;
  final Money amount;
  final String? accountId;
}

/// What a record call did.
sealed class SalaryRecordResult {
  const SalaryRecordResult();
}

/// One income was written (its id).
final class SalaryRecorded extends SalaryRecordResult {
  const SalaryRecorded(this.txnId);
  final String txnId;
}

/// A received credit already matches; nothing was written.
final class SalaryFoundExisting extends SalaryRecordResult {
  const SalaryFoundExisting(this.txnId, this.amount);
  final String txnId;
  final Money amount;
}

class SalaryService {
  SalaryService(this._db, this._repo, {required this._zone, Clock? clock})
    : _txns = TransactionsDao(_db),
      _settings = SettingsRepository(
        SettingsDao(_db),
        nowMs: () => (clock ?? DateTime.now)().toUtc().millisecondsSinceEpoch,
      );

  final AppDatabase _db;
  final TransactionRepository _repo;
  final LocalZone _zone;
  final TransactionsDao _txns;
  final SettingsRepository _settings;

  static const String incomeCategoryId = 'sys:income';

  Future<SalaryPlan?> plan() => _settings.get(Settings.salaryPlan);

  /// Sets "My salary". A null [plan] removes it (the state is kept so a
  /// later plan does not re-merge anything).
  Future<void> setPlan(SalaryPlan? plan) =>
      _settings.set(Settings.salaryPlan, plan);

  /// The expected salary on [today], or null (no plan, closed, skipped, or
  /// the next payday's window has started).
  Future<ExpectedSalary?> expected(CivilDate today) async {
    final plan = await this.plan();
    if (plan == null) return null;
    final state = await _settings.get(Settings.salaryState);
    final live = await _liveEntryIds(state);
    final p = salaryOpenPayday(
      plan: plan,
      state: state,
      today: today,
      paydayClosed: (p) =>
          state.entries.any((e) => e.anchor == p && live.contains(e.txnId)),
    );
    if (p == null) return null;
    return ExpectedSalary(p, plan.amount, plan.accountId);
  }

  /// The payday whose one nudge is due on [today], or null.
  Future<CivilDate?> nudgeDue(CivilDate today) async {
    final plan = await this.plan();
    if (plan == null) return null;
    final state = await _settings.get(Settings.salaryState);
    final live = await _liveEntryIds(state);
    final p = salaryLatestPayday(today, plan.day);
    if (!salaryNudgeDue(p, today)) return null;
    if (state.isSkipped(p) ||
        state.entries.any((e) => e.anchor == p && live.contains(e.txnId))) {
      return null;
    }
    return p;
  }

  /// "It arrived": records the planned salary as a manual income on the
  /// plan's account (or the default cash account), dated [payday].
  Future<SalaryRecordResult> confirmReceived(
    CivilDate payday, {
    required CivilDate today,
    bool allowDuplicate = false,
  }) async {
    final plan = await this.plan();
    if (plan == null) {
      throw SalaryServiceException(SalaryServiceException.noPlan);
    }
    final open = await expected(today);
    if (open == null || open.payday != payday) {
      throw SalaryServiceException(SalaryServiceException.notOpen);
    }
    final account = await _accountFor(plan.accountId, plan.currency);
    final noon = payday.epochDay * 86400000 + 12 * 3600000;
    final offset = _zone.offsetAtInstant(noon);
    return _record(
      NewTransaction(
        accountId: account,
        direction: TxnDirection.income,
        amount: plan.amount,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          noon - offset * 60000,
          isUtc: true,
        ),
        occurredTzOffsetMin: offset,
        categoryId: incomeCategoryId,
      ),
      anchor: payday,
      allowDuplicate: allowDuplicate,
      loose: true,
    );
  }

  /// A salary entered through the add flow (`Income`, `Salary`). Anchored at
  /// the plan's payday when its date falls in that window, else at its own
  /// date (a one-off).
  Future<SalaryRecordResult> recordManual(
    NewTransaction txn, {
    bool allowDuplicate = false,
  }) async {
    if (txn.direction != TxnDirection.income || !txn.amount.isPositive) {
      throw SalaryServiceException(SalaryServiceException.notOpen);
    }
    final date = CivilDate.fromLocalMs(
      txn.occurredAt.toUtc().millisecondsSinceEpoch,
      txn.occurredTzOffsetMin,
    );
    final plan = await this.plan();
    final p = plan == null ? null : salaryPaydayFor(date, plan.day);
    return _record(
      NewTransaction(
        accountId: txn.accountId,
        direction: txn.direction,
        amount: txn.amount,
        originalAmount: txn.originalAmount,
        occurredAt: txn.occurredAt,
        occurredTzOffsetMin: txn.occurredTzOffsetMin,
        categoryId: txn.categoryId ?? incomeCategoryId,
        merchant: txn.merchant,
        note: txn.note,
      ),
      anchor: p ?? date,
      allowDuplicate: allowDuplicate,
    );
  }

  /// "Same one": ties the received credit [txnId] to [payday], closing the
  /// expected item.
  Future<void> linkExisting(CivilDate payday, String txnId) =>
      _txns.inTransaction(() async {
        final state = await _settings.get(Settings.salaryState);
        await _settings.set(
          Settings.salaryState,
          state.withEntry(
            SalaryEntry(txnId: txnId, captured: true, anchor: payday),
          ),
        );
      });

  /// "Skip this month".
  Future<void> skip(CivilDate payday) => _txns.inTransaction(() async {
    final state = await _settings.get(Settings.salaryState);
    await _settings.set(Settings.salaryState, state.withSkipped(payday));
  });

  // ------------------------------------------------------------- core

  Future<SalaryRecordResult> _record(
    NewTransaction txn, {
    required CivilDate anchor,
    required bool allowDuplicate,
    bool loose = false,
  }) {
    return _txns.inTransaction(() async {
      if (!allowDuplicate) {
        final found =
            await _findTied(anchor) ??
            await _findReceived(anchor, txn.amount, loose: loose);
        if (found != null) return found;
      }
      final added = await _repo.add(await _withKnownCategory(txn));
      final state = await _settings.get(Settings.salaryState);
      await _settings.set(
        Settings.salaryState,
        state.withEntry(
          SalaryEntry(txnId: added.id, captured: false, anchor: anchor),
        ),
      );
      return SalaryRecorded(added.id);
    });
  }

  /// A live transaction already tied to [anchor] (the salary was recorded or
  /// received for that payday).
  Future<SalaryFoundExisting?> _findTied(CivilDate anchor) async {
    final state = await _settings.get(Settings.salaryState);
    for (final e in state.entries) {
      if (e.anchor != anchor) continue;
      final r = await _db
          .customSelect(
            'SELECT amount_minor, currency FROM transactions WHERE id = ?1 '
            "AND deleted_at IS NULL AND status = 'posted'",
            variables: [Variable.withString(e.txnId)],
            readsFrom: {_db.transactions},
          )
          .getSingleOrNull();
      if (r == null) continue;
      final m = Money.tryFromStorage(
        r.read<int>('amount_minor'),
        r.read<String>('currency'),
      );
      if (m != null) return SalaryFoundExisting(e.txnId, m);
    }
    return null;
  }

  /// A received (not manual) credit that matches [anchor] and [expected] and
  /// is not tied to a salary yet.
  Future<SalaryFoundExisting?> _findReceived(
    CivilDate anchor,
    Money expected, {
    bool loose = false,
  }) async {
    final state = await _settings.get(Settings.salaryState);
    final from =
        anchor.plusDays(-salaryWindowBeforeDays - 1).epochDay * 86400000 -
        14 * 3600000;
    final to =
        anchor.plusDays(salaryWindowAfterDays + 2).epochDay * 86400000 +
        14 * 3600000;
    final rows = await _db
        .customSelect(
          'SELECT id, amount_minor, currency, occurred_at, '
          'occurred_tz_offset_min, merchant_raw, counterparty_value, note '
          'FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'posted' "
          'AND is_internal = 0 AND transfer_pair_id IS NULL '
          "AND source <> 'manual' "
          "AND direction IN ('income', 'transfer_in') AND currency = ?1 "
          'AND occurred_at >= ?2 AND occurred_at <= ?3 '
          'ORDER BY occurred_at',
          variables: [
            Variable.withString(expected.currency.code),
            Variable.withInt(from),
            Variable.withInt(to),
          ],
          readsFrom: {_db.transactions},
        )
        .get();
    for (final r in rows) {
      final id = r.read<String>('id');
      if (state.entryOf(id) != null || state.declined.contains(id)) continue;
      final amount = Money.tryFromStorage(
        r.read<int>('amount_minor'),
        r.read<String>('currency'),
      );
      if (amount == null) continue;
      final c = SalaryCandidate(
        amount: amount,
        localDate: CivilDate.fromLocalMs(
          r.read<int>('occurred_at'),
          r.read<int>('occurred_tz_offset_min'),
        ),
        keyword: salaryLooksLikeSalary([
          r.readNullable<String>('merchant_raw'),
          r.readNullable<String>('counterparty_value'),
          r.readNullable<String>('note'),
        ]),
      );
      // "It arrived" is the user's question about the plan, which may be out
      // of date: any credit of at least half the plan, in the window and the
      // same currency, is offered ("is this it?"), never tied silently.
      final looseHit =
          loose &&
          salaryInWindow(anchor, c.localDate) &&
          amount.minor * 2 >= expected.minor;
      if (looseHit ||
          salaryMatches(anchor: anchor, expected: expected, credit: c)) {
        return SalaryFoundExisting(id, amount);
      }
    }
    return null;
  }

  /// The seeded income category is used only when it exists (a foreign key
  /// would refuse the row otherwise).
  Future<NewTransaction> _withKnownCategory(NewTransaction txn) async {
    final id = txn.categoryId;
    if (id == null) return txn;
    final r = await _db
        .customSelect(
          'SELECT 1 AS x FROM categories WHERE id = ?1',
          variables: [Variable.withString(id)],
          readsFrom: {_db.categories},
        )
        .getSingleOrNull();
    if (r != null) return txn;
    return NewTransaction(
      accountId: txn.accountId,
      direction: txn.direction,
      amount: txn.amount,
      originalAmount: txn.originalAmount,
      occurredAt: txn.occurredAt,
      occurredTzOffsetMin: txn.occurredTzOffsetMin,
      merchant: txn.merchant,
      note: txn.note,
    );
  }

  Future<Set<String>> _liveEntryIds(SalaryState state) async {
    final out = <String>{};
    for (final e in state.entries) {
      final r = await _db
          .customSelect(
            'SELECT 1 AS x FROM transactions WHERE id = ?1 '
            "AND deleted_at IS NULL AND status = 'posted'",
            variables: [Variable.withString(e.txnId)],
            readsFrom: {_db.transactions},
          )
          .getSingleOrNull();
      if (r != null) out.add(e.txnId);
    }
    return out;
  }

  /// [preferred] when it is a live, unmerged account; else the default cash
  /// account.
  Future<String> _accountFor(String? preferred, Currency currency) async {
    if (preferred != null) {
      final r = await _db
          .customSelect(
            'SELECT 1 AS x FROM accounts WHERE id = ?1 '
            'AND merged_into_id IS NULL',
            variables: [Variable.withString(preferred)],
            readsFrom: {_db.accounts},
          )
          .getSingleOrNull();
      if (r != null) return preferred;
    }
    final cash = await _db
        .customSelect(
          'SELECT id FROM accounts WHERE is_default_cash = 1 '
          'AND merged_into_id IS NULL',
          readsFrom: {_db.accounts},
        )
        .getSingleOrNull();
    if (cash == null) {
      throw SalaryServiceException(SalaryServiceException.noAccount);
    }
    return cash.read<String>('id');
  }
}
