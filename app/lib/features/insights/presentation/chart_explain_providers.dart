// T-108: providers behind S-21. Widgets read these; none touches the DB.
// The tier comes from the T-119 entitlement state: Free gets the basic
// explanation, Gold the deep one. The basic tier never reads previous-cycle
// data, so Free can't leak deep content.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/application/budget_providers.dart';
import '../../budget/presentation/budget_providers_ui.dart';
import '../../gold/application/gating.dart';
import '../application/chart_gate.dart';
import '../data/chart_providers.dart';
import '../domain/chart_models.dart';
import '../domain/explanations.dart';
import 'charts/charts_providers.dart';

/// Charts that have a query provider and explanation input today.
const Set<ChartId> explainableCharts = {
  ChartId.cashFlow,
  ChartId.categoryDonut,
  ChartId.topMerchants,
  ChartId.burnCurve,
  ChartId.fiftyThirtyTwenty,
  ChartId.dayHourPattern,
  ChartId.monthVsAverage,
  ChartId.installmentTimeline,
  ChartId.subscriptionsAnnual,
  ChartId.cardsSplit,
  ChartId.netWorth,
};

typedef ChartExplainKey = ({ChartId chart, String code});

/// The engine's result, or why there was not enough data (EC-23).
typedef ExplainOutcome = ({Explanation explanation, NotEnoughReason? reason});

/// Real catalog ids of essential categories (Q-25): rows in the needs and
/// obligations buckets. Tips never target them.
final essentialCategoryIdsProvider = FutureProvider<Set<String>>((ref) async {
  final rows = await ref.watch(categoryRowsProvider.future);
  return {
    for (final r in rows)
      if (r.bucket == 'needs' || r.bucket == 'obligations') r.id,
  };
}, name: 'essentialCategoryIdsProvider');

/// The previous period of the same kind and length (T-188): the cycle,
/// month, block of months, year or custom range one step back.
final previousDonutChartProvider =
    FutureProvider.family<ChartResult<CategoryDonut>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.categoryDonut(
        resolved.previous,
        ChartFilter(currency: Currency.of(code)),
      );
    }, name: 'previousDonutChartProvider');

final previousMerchantsChartProvider =
    FutureProvider.family<ChartResult<List<MerchantSpend>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.topMerchants(
        resolved.previous,
        ChartFilter(currency: Currency.of(code)),
        limit: topMerchantsLimitFor(ref.watch(entitlementStateProvider)),
      );
    }, name: 'previousMerchantsChartProvider');

/// One point for the previous period as a whole (cash flow explainer).
final previousCashFlowTotalProvider =
    FutureProvider.family<ChartResult<List<CashFlowPoint>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cashFlow([
        resolved.previous,
      ], ChartFilter(currency: Currency.of(code)));
    }, name: 'previousCashFlowTotalProvider');

final previousBurnChartProvider =
    FutureProvider.family<ChartResult<BurnCurve>, String>((ref, code) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      if (resolved.cycle == null) {
        return const ChartNotEnoughData<BurnCurve>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        );
      }
      final repo = await ref.watch(chartRepositoryProvider.future);
      // The whole earlier cycle, read up to the same day as now (to-date).
      final prev = Cycle(
        start: resolved.previousFull.from,
        end: resolved.previousFull.to,
      );
      return repo.burnCurve(
        prev,
        resolved.previous.to,
        ChartFilter(currency: Currency.of(code)),
      );
    }, name: 'previousBurnChartProvider');

final previousRule503020ChartProvider =
    FutureProvider.family<ChartResult<FiftyThirtyTwenty>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.fiftyThirtyTwenty(
        resolved.previous,
        ChartFilter(currency: Currency.of(code)),
      );
    }, name: 'previousRule503020ChartProvider');

final previousCardsChartProvider =
    FutureProvider.family<ChartResult<List<CardSpend>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final repo = await ref.watch(chartRepositoryProvider.future);
      return repo.cardsSplit(
        resolved.previous,
        ChartFilter(currency: Currency.of(code)),
      );
    }, name: 'previousCardsChartProvider');

T? _ready<T>(ChartResult<T>? r) => switch (r) {
  ChartReady<T>(:final data) => data,
  _ => null,
};

NotEnoughReason? _reasonOf(ChartResult<Object?> r) => switch (r) {
  ChartNotEnoughData(:final reason) => reason,
  _ => null,
};

final _rawExplanationProvider =
    FutureProvider.family<ExplainOutcome, ChartExplainKey>((ref, key) async {
      final tier = tierFor(isGold: ref.watch(entitlementStateProvider).isGold);
      final deep = tier == ExplanationTier.deep;
      final context = ExplainContext(
        essentialCategoryIds: await ref.watch(
          essentialCategoryIdsProvider.future,
        ),
      );
      Explanation empty() => Explanation(key.chart, tier, const []);
      switch (key.chart) {
        case ChartId.cashFlow:
          final r = await ref.watch(cashFlowTotalProvider(key.code).future);
          final points = _ready(r);
          if (points == null || points.isEmpty) {
            return (explanation: empty(), reason: _reasonOf(r));
          }
          final donut = _ready(
            await ref.watch(donutChartProvider(key.code).future),
          );
          final prev = deep
              ? _ready(
                  await ref.watch(
                    previousCashFlowTotalProvider(key.code).future,
                  ),
                )
              : null;
          return (
            explanation: explainChart(
              CashFlowExplainInput(
                current: points.last,
                previous: prev == null || prev.isEmpty ? null : prev.last,
                categories: donut?.slices ?? const [],
              ),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.categoryDonut:
          final r = await ref.watch(donutChartProvider(key.code).future);
          final donut = _ready(r);
          if (donut == null) {
            return (explanation: empty(), reason: _reasonOf(r));
          }
          final prev = deep
              ? _ready(
                  await ref.watch(previousDonutChartProvider(key.code).future),
                )
              : null;
          return (
            explanation: explainChart(
              CategoriesExplainInput(current: donut, previous: prev),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.topMerchants:
          final r = await ref.watch(merchantsChartProvider(key.code).future);
          final rows = _ready(r);
          if (rows == null) {
            return (explanation: empty(), reason: _reasonOf(r));
          }
          final prev = deep
              ? _ready(
                  await ref.watch(
                    previousMerchantsChartProvider(key.code).future,
                  ),
                )
              : null;
          return (
            explanation: explainChart(
              MerchantsExplainInput(current: rows, previous: prev ?? const []),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.burnCurve:
          final r = await ref.watch(burnChartProvider(key.code).future);
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          final prev = deep
              ? _ready(
                  await ref.watch(previousBurnChartProvider(key.code).future),
                )
              : null;
          return (
            explanation: explainChart(
              BurnRateExplainInput(current: cur, previous: prev),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.fiftyThirtyTwenty:
          final r = await ref.watch(rule503020ChartProvider(key.code).future);
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          final prev = deep
              ? _ready(
                  await ref.watch(
                    previousRule503020ChartProvider(key.code).future,
                  ),
                )
              : null;
          return (
            explanation: explainChart(
              Rule503020ExplainInput(current: cur, previous: prev),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.dayHourPattern:
          final r = await ref.watch(dayHourChartProvider(key.code).future);
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          final period = await ref.watch(dayHourPeriodProvider.future);
          return (
            explanation: explainChart(
              WeekPatternExplainInput(current: cur, period: period),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.monthVsAverage:
          final r = await ref.watch(vsAverageChartProvider(key.code).future);
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          return (
            explanation: explainChart(
              VsAverageExplainInput(current: cur),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.installmentTimeline:
          final r = await ref.watch(installmentsChartProvider(key.code).future);
          final months = _ready(r);
          if (months == null || months.isEmpty) {
            return (explanation: empty(), reason: _reasonOf(r));
          }
          return (
            explanation: explainChart(
              InstallmentsExplainInput(
                months: months,
                ends: const [],
                today: ref.watch(todayProvider),
              ),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.subscriptionsAnnual:
          final r = await ref.watch(
            subscriptionsChartProvider(key.code).future,
          );
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          return (
            explanation: explainChart(
              SubscriptionsExplainInput(current: cur),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.cardsSplit:
          final r = await ref.watch(cardsChartProvider(key.code).future);
          final cur = _ready(r);
          if (cur == null) return (explanation: empty(), reason: _reasonOf(r));
          final prev = deep
              ? _ready(
                  await ref.watch(previousCardsChartProvider(key.code).future),
                )
              : null;
          return (
            explanation: explainChart(
              CardsExplainInput(current: cur, previous: prev ?? const []),
              tier,
              context: context,
            ),
            reason: null,
          );
        case ChartId.netWorth:
          final r = await ref.watch(netWorthChartProvider(key.code).future);
          final pts = _ready(r);
          if (pts == null) return (explanation: empty(), reason: _reasonOf(r));
          return (
            explanation: explainChart(
              NetWorthExplainInput(points: pts),
              tier,
              context: context,
            ),
            reason: null,
          );
        default:
          return (explanation: empty(), reason: NotEnoughReason.noData);
      }
    }, name: '_rawExplanationProvider');

/// The explanation for the chosen period. The tip lines say "next cycle" and
/// "a year" and their targets are sized for one cycle, so they are shown
/// only when the period is a cycle; other periods get the facts (T-188,
/// design note §6).
final chartExplanationProvider =
    FutureProvider.family<ExplainOutcome, ChartExplainKey>((ref, key) async {
      final outcome = await ref.watch(_rawExplanationProvider(key).future);
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      if (resolved.isCycle || outcome.explanation.isEmpty) return outcome;
      final e = outcome.explanation;
      return (
        explanation: Explanation(e.chart, e.tier, [
          for (final line in e.lines)
            if (line.key.part != ExplanationPart.tip &&
                line.key.part != ExplanationPart.deepTip)
              line,
        ]),
        reason: outcome.reason,
      );
    }, name: 'chartExplanationProvider');
