// T-107: providers behind the Charts segment (S-20). Widgets read these;
// none touches the DB. Each chart has its own provider so one failure never
// blanks the page (C-29).

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/application/budget_providers.dart';
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../data/chart_providers.dart';
import '../../domain/chart_models.dart';

/// How many cycles the cash flow chart shows (the newest is the current one).
const int cashFlowBuckets = 6;

final chartsCurrentCycleProvider = FutureProvider<Cycle>((ref) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  return schedule.cycleOn(ref.watch(todayProvider));
}, name: 'chartsCurrentCycleProvider');

/// Currencies with activity in the current cycle (FR-CHT-05).
final chartsCurrenciesProvider = FutureProvider<List<Currency>>((ref) async {
  final cycle = await ref.watch(chartsCurrentCycleProvider.future);
  final repo = await ref.watch(chartRepositoryProvider.future);
  return repo.currenciesWithActivity(ChartPeriod.cycle(cycle));
}, name: 'chartsCurrenciesProvider');

/// The chosen currency code; null means the first one with activity.
final chartsCurrencyProvider = NotifierProvider<ChartsCurrency, String?>(
  ChartsCurrency.new,
  name: 'chartsCurrencyProvider',
);

class ChartsCurrency extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String code) => state = code;
}

final cashFlowChartProvider =
    FutureProvider.family<ChartResult<List<CashFlowPoint>>, String>((
      ref,
      code,
    ) async {
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final cycles = <Cycle>[cycle];
      for (var i = 1; i < cashFlowBuckets; i++) {
        cycles.insert(0, schedule.before(cycles.first));
      }
      return repo.cashFlow([
        for (final c in cycles) ChartPeriod.cycle(c),
      ], ChartFilter(currency: Currency.of(code)));
    }, name: 'cashFlowChartProvider');

final donutChartProvider =
    FutureProvider.family<ChartResult<CategoryDonut>, String>((
      ref,
      code,
    ) async {
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.categoryDonut(
        ChartPeriod.cycle(cycle),
        ChartFilter(currency: Currency.of(code)),
      );
    }, name: 'donutChartProvider');

/// Free sees the top 5 (FR-CHT-02); Gold more.
final merchantsChartProvider =
    FutureProvider.family<ChartResult<List<MerchantSpend>>, String>((
      ref,
      code,
    ) async {
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final limit = topMerchantsLimitFor(ref.watch(entitlementStateProvider));
      return repo.topMerchants(
        ChartPeriod.cycle(cycle),
        ChartFilter(currency: Currency.of(code)),
        limit: limit,
      );
    }, name: 'merchantsChartProvider');

ChartFilter _filter(String code) => ChartFilter(currency: Currency.of(code));

/// Cumulative spend by cycle day (chart 3).
final burnChartProvider = FutureProvider.family<ChartResult<BurnCurve>, String>(
  (ref, code) async {
    final cycle = await ref.watch(chartsCurrentCycleProvider.future);
    final repo = await ref.watch(chartRepositoryProvider.future);
    return repo.burnCurve(cycle, ref.watch(todayProvider), _filter(code));
  },
  name: 'burnChartProvider',
);

final rule503020ChartProvider =
    FutureProvider.family<ChartResult<FiftyThirtyTwenty>, String>((
      ref,
      code,
    ) async {
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.fiftyThirtyTwenty(ChartPeriod.cycle(cycle), _filter(code));
    }, name: 'rule503020ChartProvider');

/// The window behind the day/hour pattern: the last three cycles, because
/// a habit needs more than one cycle of rows.
final dayHourPeriodProvider = FutureProvider<ChartPeriod>((ref) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final cycle = await ref.watch(chartsCurrentCycleProvider.future);
  final older = schedule.before(schedule.before(cycle));
  return ChartPeriod(older.start, cycle.end);
}, name: 'dayHourPeriodProvider');

final dayHourChartProvider =
    FutureProvider.family<ChartResult<DayHourPattern>, String>((
      ref,
      code,
    ) async {
      final period = await ref.watch(dayHourPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.dayHourPattern(period, _filter(code));
    }, name: 'dayHourChartProvider');

final vsAverageChartProvider =
    FutureProvider.family<ChartResult<MonthVsAverage>, String>((
      ref,
      code,
    ) async {
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final priors = <ChartPeriod>[];
      var c = cycle;
      for (var i = 0; i < ChartThresholds.averageMaxCycles; i++) {
        c = schedule.before(c);
        priors.add(ChartPeriod.cycle(c));
      }
      return repo.monthVsAverage(
        ChartPeriod.cycle(cycle),
        priors,
        ref.watch(todayProvider),
        _filter(code),
      );
    }, name: 'vsAverageChartProvider');

final installmentsChartProvider =
    FutureProvider.family<ChartResult<List<InstallmentMonth>>, String>((
      ref,
      code,
    ) async {
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.installmentTimeline(ref.watch(todayProvider), _filter(code));
    }, name: 'installmentsChartProvider');

final subscriptionsChartProvider =
    FutureProvider.family<ChartResult<SubscriptionsAnnual>, String>((
      ref,
      code,
    ) async {
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.subscriptionsAnnual(_filter(code));
    }, name: 'subscriptionsChartProvider');

final cardsChartProvider =
    FutureProvider.family<ChartResult<List<CardSpend>>, String>((
      ref,
      code,
    ) async {
      final cycle = await ref.watch(chartsCurrentCycleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cardsSplit(ChartPeriod.cycle(cycle), _filter(code));
    }, name: 'cardsChartProvider');

/// Net worth snapshots of one unit over the last twelve months. The unit is
/// the currency code; units are never combined.
final netWorthChartProvider =
    FutureProvider.family<ChartResult<List<NetWorthPoint>>, String>((
      ref,
      code,
    ) async {
      final repo = await ref.watch(chartRepositoryProvider.future);
      final today = ref.watch(todayProvider);
      final startIdx = today.year * 12 + today.month - 1 - 11;
      final from = CivilDate(startIdx ~/ 12, startIdx % 12 + 1, 1);
      return repo.netWorth(ChartPeriod(from, today), code);
    }, name: 'netWorthChartProvider');

final inflationChartProvider =
    FutureProvider.family<ChartResult<List<InflationPoint>>, String>((
      ref,
      code,
    ) async {
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.personalInflationIndex(
        ref.watch(todayProvider),
        _filter(code),
      );
    }, name: 'inflationChartProvider');

/// Opens a card (S-41) from the cards split chart. Null until the shell
/// wires it; rows are then plain, not tappable.
final chartCardOpenerProvider =
    Provider<void Function(BuildContext, String accountId)?>(
      (ref) => null,
      name: 'chartCardOpenerProvider',
    );

/// The charts Free users see locked, in S-20 order.
const List<ChartId> lockedChartOrder = [
  ChartId.burnCurve,
  ChartId.fiftyThirtyTwenty,
  ChartId.dayHourPattern,
  ChartId.monthVsAverage,
  ChartId.installmentTimeline,
  ChartId.subscriptionsAnnual,
  ChartId.cardsSplit,
  ChartId.netWorth,
  ChartId.personalInflation,
];
