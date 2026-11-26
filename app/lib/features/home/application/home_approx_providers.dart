// T-280 (D-86): Riverpod wiring for the Home "≈ money in" line and its Q2
// first-time switch-on. Reads only; the one write is the once-only switch-on.
// Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart';
import '../../wealth/data/prices_providers.dart';
import '../../wealth/domain/income_approx.dart';

/// This cycle's totals for all cards, per currency (public for tests).
final homeApproxCycleTotalsProvider =
    FutureProvider<Map<Currency, CycleTotals>>((ref) async {
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final repo = await ref.watch(cycleRepositoryProvider.future);
      ref.watch(cycleDataVersionProvider);
      return repo.totals(schedule.cycleOn(ref.watch(todayProvider)));
    }, name: 'homeApproxCycleTotalsProvider');

bool _active(CycleTotals t) =>
    t.moneyIn.minor != 0 || t.spend.minor != 0 || t.exchangedOut.minor != 0;

/// The figure, or null when no line is shown (setting off, nothing foreign
/// or a rate is missing).
final homeApproxProvider = FutureProvider<IncomeApproxLine?>((ref) async {
  if (!await ref.watch(approxViewEnabledProvider.future)) return null;
  final target = await ref.watch(approxViewTargetProvider.future);
  final totals = await ref.watch(homeApproxCycleTotalsProvider.future);
  final repo = await ref.watch(pricesRepositoryProvider.future);

  // The bank's rate can be attributed only when exactly one foreign currency
  // exchanged anything; otherwise it is left out (display only anyway).
  final foreignExchanged = [
    for (final t in totals.values)
      if (t.currency != target && t.exchangedOut.isPositive) t,
  ];
  int? bankRate;
  final targetIn = totals[target]?.exchangedIn;
  if (foreignExchanged.length == 1 && targetIn != null && targetIn.isPositive) {
    bankRate = impliedRateE9(foreignExchanged.single.exchangedOut, targetIn);
  }

  final result = buildIncomeApprox(
    target: target,
    inputs: [
      for (final t in totals.values)
        IncomeApproxInput(
          moneyIn: t.moneyIn,
          exchangedOut: t.exchangedOut,
          bankRateE9:
              foreignExchanged.length == 1 && foreignExchanged.single == t
              ? bankRate
              : null,
        ),
    ],
    rates: await repo.fxTable(),
    nowMs: ref.watch(pricesClockProvider)().millisecondsSinceEpoch,
  );
  return result is IncomeApproxLine ? result : null;
}, name: 'homeApproxProvider');

/// Q2: the first time two currencies have activity, turn the ≈ view on once
/// and raise the Captain's notice. The done flag is never reset, so a user
/// who turns the view off is not switched on again.
final homeApproxAutoOnProvider = FutureProvider<void>((ref) async {
  final totals = await ref.watch(homeApproxCycleTotalsProvider.future);
  // Read, never watched: this provider writes these flags itself.
  final settings = await ref.read(settingsRepositoryProvider.future);
  final done = await settings.get(Settings.approxAutoOnDone);
  if (!shouldAutoEnableApprox(
    activeCurrencies: totals.values.where(_active).length,
    alreadyDone: done,
  )) {
    return;
  }
  final alreadyOn = await settings.get(Settings.approxViewEnabled);
  // Mark done first: a crash in between never switches it on twice.
  await settings.set(Settings.approxAutoOnDone, true);
  if (!alreadyOn) {
    await settings.set(Settings.approxViewEnabled, true);
    await settings.set(Settings.approxFirstForeignNotice, true);
  }
}, name: 'homeApproxAutoOnProvider');
