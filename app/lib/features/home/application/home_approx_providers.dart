// T-280 (D-86): Riverpod wiring for the Home "≈ money in" line and its Q2
// first-time switch-on. Reads only; the one write is the once-only switch-on.
// Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart';
import '../../insights/data/chart_providers.dart';
import '../../insights/domain/chart_models.dart';
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

/// This cycle's complete exchange pairs (given, received), live legs only.
final homeApproxExchangePairsProvider =
    FutureProvider<List<({Money given, Money received})>>((ref) async {
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final charts = await ref.watch(chartRepositoryProvider.future);
      ref.watch(cycleDataVersionProvider);
      return charts.exchangePairs(
        ChartPeriod.cycle(schedule.cycleOn(ref.watch(todayProvider))),
      );
    }, name: 'homeApproxExchangePairsProvider');

/// The bank's rate per foreign currency, from the pairs that went into
/// [target] only (FU-381): exchanges into a third currency never count.
/// Display only.
Map<Currency, int?> bankRatesE9(
  List<({Money given, Money received})> pairs,
  Currency target,
) {
  final given = <Currency, Money>{};
  final received = <Currency, Money>{};
  for (final x in pairs) {
    if (x.received.currency != target || x.given.currency == target) continue;
    final c = x.given.currency;
    given[c] = (given[c] ?? Money.zero(c)) + x.given;
    received[c] = (received[c] ?? Money.zero(target)) + x.received;
  }
  return {
    for (final c in given.keys) c: impliedRateE9(given[c]!, received[c]!),
  };
}

bool _active(CycleTotals t) =>
    t.moneyIn.minor != 0 || t.spend.minor != 0 || t.exchangedOut.minor != 0;

/// The figure, or null when no line is shown (setting off, nothing foreign
/// or a rate is missing).
final homeApproxProvider = FutureProvider<IncomeApproxLine?>((ref) async {
  if (!await ref.watch(approxViewEnabledProvider.future)) return null;
  final target = await ref.watch(approxViewTargetProvider.future);
  final totals = await ref.watch(homeApproxCycleTotalsProvider.future);
  final repo = await ref.watch(pricesRepositoryProvider.future);

  final pairs = await ref.watch(homeApproxExchangePairsProvider.future);
  final bankRates = bankRatesE9(pairs, target);

  final result = buildIncomeApprox(
    target: target,
    inputs: [
      for (final t in totals.values)
        IncomeApproxInput(
          moneyIn: t.moneyIn,
          exchangedOut: t.exchangedOut,
          bankRateE9: bankRates[t.currency],
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
