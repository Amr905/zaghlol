// T-107: providers behind the Charts segment (S-20). Widgets read these;
// none touches the DB. Each chart has its own provider so one failure never
// blanks the page (C-29).

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
