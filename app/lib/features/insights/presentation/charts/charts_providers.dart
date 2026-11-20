// T-107: providers behind the Charts segment (S-20). Widgets read these;
// none touches the DB. Each chart has its own provider so one failure never
// blanks the page (C-29). T-188: every chart follows the chosen period
// (`chartsResolvedPeriodProvider`).

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/application/budget_providers.dart';
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../application/chart_period_providers.dart';
import '../../data/chart_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';

export '../../application/chart_period_providers.dart';

ChartFilter _filter(String code) => ChartFilter(currency: Currency.of(code));

/// Why a cycle-only chart (burn rate, month vs average) has nothing for a
/// period that is not a cycle. The cards check `supports` first and show
/// the note; this keeps the providers total.
const ChartNotEnoughData<Never> _needsCycle = ChartNotEnoughData<Never>(
  NotEnoughReason.noData,
  have: 0,
  need: 1,
);

/// Currencies with activity in the chosen period (FR-CHT-05).
final chartsCurrenciesProvider = FutureProvider<List<Currency>>((ref) async {
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  final repo = await ref.watch(chartRepositoryProvider.future);
  return repo.currenciesWithActivity(resolved.period);
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

/// Income and spend per bucket: six cycles for a cycle period, else days,
/// weeks or months by the period's length (design note §2).
final cashFlowChartProvider =
    FutureProvider.family<ChartResult<List<CashFlowPoint>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cashFlow(
        cashFlowBuckets(resolved, ref.watch(todayProvider), schedule),
        _filter(code),
      );
    }, name: 'cashFlowChartProvider');

/// The points the footnote and the text summary describe: the whole chosen
/// period (a cycle period draws six cycles but speaks about the chosen one).
List<CashFlowPoint> cashFlowPeriodPoints(
  AsyncValue<ChartResult<List<CashFlowPoint>>> total,
  List<CashFlowPoint> drawn,
) => switch (total.value) {
  ChartReady<List<CashFlowPoint>>(:final data) when data.isNotEmpty => data,
  _ => drawn,
};

/// One point for the whole period (the footnote and the explainer).
final cashFlowTotalProvider =
    FutureProvider.family<ChartResult<List<CashFlowPoint>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cashFlow([resolved.period], _filter(code));
    }, name: 'cashFlowTotalProvider');

final donutChartProvider =
    FutureProvider.family<ChartResult<CategoryDonut>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.categoryDonut(resolved.period, _filter(code));
    }, name: 'donutChartProvider');

/// Free sees the top 5 (FR-CHT-02); Gold more.
final merchantsChartProvider =
    FutureProvider.family<ChartResult<List<MerchantSpend>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final limit = topMerchantsLimitFor(ref.watch(entitlementStateProvider));
      return repo.topMerchants(resolved.period, _filter(code), limit: limit);
    }, name: 'merchantsChartProvider');

/// Cumulative spend by cycle day (chart 3). Cycle periods only; a past
/// cycle runs to its last day.
final burnChartProvider = FutureProvider.family<ChartResult<BurnCurve>, String>(
  (ref, code) async {
    final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
    final cycle = resolved.cycle;
    if (cycle == null) return _needsCycle;
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
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.fiftyThirtyTwenty(resolved.period, _filter(code));
    }, name: 'rule503020ChartProvider');

/// The window behind the day/hour pattern: the chosen period (it used to be
/// the last three cycles; the chart's own minimum-rows rule says when that
/// is too little).
final dayHourPeriodProvider = FutureProvider<ChartPeriod>(
  (ref) async => (await ref.watch(chartsResolvedPeriodProvider.future)).period,
  name: 'dayHourPeriodProvider',
);

final dayHourChartProvider =
    FutureProvider.family<ChartResult<DayHourPattern>, String>((
      ref,
      code,
    ) async {
      final period = await ref.watch(dayHourPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.dayHourPattern(period, _filter(code));
    }, name: 'dayHourChartProvider');

/// The period so far against the mean of the cycles before it. Cycle
/// periods only.
final vsAverageChartProvider =
    FutureProvider.family<ChartResult<MonthVsAverage>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      var cycle = resolved.cycle;
      if (cycle == null) return _needsCycle;
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final priors = <ChartPeriod>[];
      for (var i = 0; i < ChartThresholds.averageMaxCycles; i++) {
        cycle = schedule.before(cycle!);
        priors.add(ChartPeriod.cycle(cycle));
      }
      return repo.monthVsAverage(
        resolved.period,
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
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cardsSplit(resolved.period, _filter(code));
    }, name: 'cardsChartProvider');

/// Net worth snapshots of one unit over the period, widened to at least
/// twelve months ending at the period's end (never past today). The unit is
/// the currency code; units are never combined.
final netWorthChartProvider =
    FutureProvider.family<ChartResult<List<NetWorthPoint>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final today = ref.watch(todayProvider);
      final p = resolved.period;
      final capped = p.to > today
          ? ChartPeriod(p.from <= today ? p.from : today, today)
          : p;
      return repo.netWorth(netWorthRange(capped), code);
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
