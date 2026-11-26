// T-215 / T-294: decides when Captain Zaghlol celebrates a payday
// (08-mascot-motion section 1: "salary detected, once per salary"). The Home
// slot reads [paydayCelebrationProvider] and opens the payday sheet. Salaries
// of any currency count (D-85), from a bank message or entered by hand
// (cash). Nothing logs an amount.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../../salary/application/salary_providers.dart';
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/domain/transaction.dart';

/// A salary tied to a payday older than this many days is history (e.g. the
/// first import of old messages) and never celebrates.
const int kPaydayFreshDays = 7;

/// How many celebrated ids are remembered.
const int kPaydayRememberedIds = 32;

/// The salary to celebrate: its transaction and its own amount.
final class PaydayCelebration {
  const PaydayCelebration(this.txnId, this.amount);
  final String txnId;
  final Money amount;
}

/// What to do with the salary entries not celebrated yet.
final class PaydayDecision {
  const PaydayDecision({required this.fresh, required this.all});

  /// Fresh candidates, newest anchor first.
  final List<SalaryEntry> fresh;

  /// Every candidate (fresh or old): all get marked as celebrated.
  final List<SalaryEntry> all;
}

/// Pure. [celebrated] are the remembered txn ids; [legacyMarkEpochDay] is the
/// anchor day stored by the first (T-215) version, or null.
PaydayDecision paydayDecision({
  required SalaryState state,
  required Set<String> celebrated,
  required int? legacyMarkEpochDay,
  required CivilDate today,
}) {
  final all = [
    for (final e in state.entries)
      if (!celebrated.contains(e.txnId) &&
          (legacyMarkEpochDay == null ||
              e.anchor.epochDay > legacyMarkEpochDay))
        e,
  ];
  final fresh = [
    for (final e in all)
      if (today.difference(e.anchor) <= kPaydayFreshDays) e,
  ]..sort((a, b) => b.anchor.epochDay.compareTo(a.anchor.epochDay));
  return PaydayDecision(fresh: fresh, all: all);
}

/// Emits the salary to celebrate (once), after storing it as celebrated.
/// Old, deleted and non-income salaries are stored silently. Survives
/// restarts: the marks are in the encrypted settings.
final paydayCelebrationProvider = StreamProvider<PaydayCelebration?>((
  ref,
) async* {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  final state = ref.watch(salaryStateProvider).value;
  final today = ref.watch(todayProvider);
  if (state == null) {
    yield null;
    return;
  }
  final done = await repo.get(Settings.mascotPaydayCelebratedTxns);
  final legacy = await repo.get(Settings.mascotPaydayCelebrated);
  final d = paydayDecision(
    state: state,
    celebrated: done.toSet(),
    legacyMarkEpochDay: legacy,
    today: today,
  );
  if (d.all.isEmpty) {
    yield null;
    return;
  }
  PaydayCelebration? pick;
  if (d.fresh.isNotEmpty) {
    final txns = await ref.read(transactionRepositoryProvider.future);
    for (final e in d.fresh) {
      final t = await txns.byId(e.txnId);
      if (t != null && t.direction == TxnDirection.income) {
        pick = PaydayCelebration(t.id, t.amount);
        break;
      }
    }
  }
  final next = [...done, for (final e in d.all) e.txnId];
  await repo.set(
    Settings.mascotPaydayCelebratedTxns,
    next.length <= kPaydayRememberedIds
        ? next
        : next.sublist(next.length - kPaydayRememberedIds),
  );
  yield pick;
});
