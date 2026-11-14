// T-105 / FU-123: maps the Free tier's "4 core charts" (SRS §5.2, FR-CHT-02)
// to the real chart set. Free: cash flow (1), category donut (2), top
// merchants (6, top 5 only) and the budget progress bars (A-06). Everything
// else shows a Gold-locked preview. Viewing is decided by [GoldGate.chart]
// on the index below, so the Gold matrix stays in one place.

import '../../gold/application/gating.dart';
import '../domain/chart_models.dart';

/// The position of each chart in the gate's "ordered chart list": the four
/// core charts are 0..3, the rest follow in FR-CHT-01 order.
int chartGateIndex(ChartId id) => switch (id) {
  ChartId.cashFlow => 0,
  ChartId.categoryDonut => 1,
  ChartId.topMerchants => 2,
  ChartId.budgetProgress => 3,
  ChartId.burnCurve => 4,
  ChartId.fiftyThirtyTwenty => 5,
  ChartId.dayHourPattern => 6,
  ChartId.monthVsAverage => 7,
  ChartId.installmentTimeline => 8,
  ChartId.subscriptionsAnnual => 9,
  ChartId.cardsSplit => 10,
  ChartId.netWorth => 11,
  ChartId.personalInflation => 12,
};

/// Whether [state] may open [id], or must see the locked preview.
GateDecision decideChart(EntitlementState state, ChartId id) =>
    GoldGate.chart(state, chartGateIndex(id));

/// The row limit of the top merchants chart for [state]: 5 for Free.
int topMerchantsLimitFor(EntitlementState state, {int goldLimit = 10}) =>
    state.isGold ? goldLimit : ChartThresholds.freeTopMerchants;
