// T-209 (CHARTS-V2): providers behind the Overview tab. Widgets read these;
// none touches the DB. The hero speaks the primary currency; the others with
// spending in the period are listed in their own currency, never summed
// (D-28/D-29).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/settings/settings_providers.dart';
import '../../../budget/application/budget_providers.dart';
import '../../data/chart_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';
import '../../domain/chart_summary.dart';
import '../../domain/overview_models.dart';
import '../../domain/pace.dart';
import '../../domain/saved_months.dart';
import '../charts/charts_providers.dart';

ChartFilter _filter(String code) => ChartFilter(currency: Currency.of(code));

/// The currency of the hero: the primary currency, else the first one with
/// activity in the period, else EGP.
final overviewCurrencyProvider = FutureProvider<String>((ref) async {
  final primary = ref.watch(primaryCurrencyProvider).value;
  if (primary != null) return primary.code;
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  final repo = await ref.watch(chartRepositoryProvider.future);
  final list = await repo.currenciesWithActivity(resolved.period);
  return list.isEmpty ? 'EGP' : list.first.code;
}, name: 'overviewCurrencyProvider');

/// The pace of the chosen period in [code] (the budget line only for a
/// payday cycle, which is what the budget is set for).
final paceProvider = FutureProvider.family<PaceData, String>((ref, code) async {
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  final today = ref.watch(todayProvider);
  final repo = await ref.watch(chartRepositoryProvider.future);
  final f = _filter(code);
  final p = resolved.period;
  final daily = await repo.dailySpend(p, f);
  final prev = await repo.dailySpend(resolved.previousFull, f);
  final budget = resolved.isCycle ? await repo.overallBudget(f.currency) : null;
  return computePace(
    dailyThis: daily,
    dailyPrev: prev,
    periodDays: p.lengthDays,
    elapsedDays: today.difference(p.from) + 1,
    closed: p.to < today,
    budgetMinor: budget?.minor,
  );
}, name: 'paceProvider');

/// Income, spend and saved of the chosen period in [code].
final overviewTotalsProvider = FutureProvider.family<PeriodTotals, String>((
  ref,
  code,
) async {
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  return ref.watch(periodTotalsProvider((code, resolved.period)).future);
}, name: 'overviewTotalsProvider');

/// Spend of every other currency with spending in the period, each in its own
/// currency (never summed with the hero's).
final otherCurrencySpendProvider = FutureProvider.family<List<Money>, String>((
  ref,
  code,
) async {
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  final repo = await ref.watch(chartRepositoryProvider.future);
  final list = await repo.currenciesWithActivity(resolved.period);
  final out = <Money>[];
  for (final c in list) {
    if (c.code == code) continue;
    final t = await ref.watch(
      periodTotalsProvider((c.code, resolved.period)).future,
    );
    if (t.spend.minor > 0) out.add(t.spend);
  }
  return out;
}, name: 'otherCurrencySpendProvider');

/// The last six buckets (payday cycles for a cycle period, else calendar
/// months) ending at the chosen period, income minus spend.
final savedMonthsProvider =
    FutureProvider.family<ChartResult<SavedMonths>, String>((ref, code) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final today = ref.watch(todayProvider);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final buckets = savedBuckets(resolved, schedule);
      final r = await repo.cashFlow(buckets, _filter(code));
      return switch (r) {
        ChartReady<List<CashFlowPoint>>(:final data) => ChartReady(
          savedMonths(data, today),
        ),
        ChartNotEnoughData<List<CashFlowPoint>>(
          :final reason,
          :final have,
          :final need,
        ) =>
          ChartNotEnoughData<SavedMonths>(reason, have: have, need: need),
      };
    }, name: 'savedMonthsProvider');

/// The six buckets of "saved each month", oldest first, the last one holding
/// the end of the chosen period.
List<ChartPeriod> savedBuckets(
  ResolvedChartPeriod r,
  PaydaySchedule schedule, {
  int count = 6,
}) {
  if (r.bucketKind == ChartBucketKind.cycle) {
    var c = schedule.cycleOn(r.period.to);
    final out = <ChartPeriod>[ChartPeriod.cycle(c)];
    for (var i = 1; i < count; i++) {
      c = schedule.before(c);
      out.insert(0, ChartPeriod.cycle(c));
    }
    return out;
  }
  final end = r.period.to;
  return [
    for (var i = count - 1; i >= 0; i--)
      () {
        final idx = end.year * 12 + end.month - 1 - i;
        return ChartPeriod.month(idx ~/ 12, idx % 12 + 1);
      }(),
  ];
}

/// All upcoming dues in [code] (the Overview takes the next three and the
/// sum up to the end of the period from them).
final upcomingDuesProvider = FutureProvider.family<List<UpcomingDue>, String>((
  ref,
  code,
) async {
  final repo = await ref.watch(chartRepositoryProvider.future);
  return repo.upcomingDues(ref.watch(todayProvider), _filter(code));
}, name: 'upcomingDuesProvider');
