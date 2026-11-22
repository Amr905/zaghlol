// T-107 test support: synthetic chart data and provider overrides.

import 'package:flutter/widgets.dart' show Key;
import 'package:zaghlol/core/db/app_database.dart' show CategoryRow;
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/presentation/budget_test_support.dart';

export '../../../budget/presentation/budget_test_support.dart';

/// T-188: the clock and payday behind the period chip in widget tests.
final CivilDate chartsToday = CivilDate(2026, 11, 10);

class ChartsFixedToday extends TodayNotifier {
  @override
  CivilDate build() => chartsToday;
}

/// A selection store that never touches the settings table. [last] holds
/// what was selected most recently (null until a select).
class FakeChartPeriodSelection extends ChartPeriodSelectionNotifier {
  FakeChartPeriodSelection([this.initial = ChartPeriodSelection.thisCycle]);
  final ChartPeriodSelection initial;
  static ChartPeriodSelection? last;

  @override
  Future<ChartPeriodSelection> build() async => initial;

  @override
  Future<void> select(ChartPeriodSelection selection) async {
    last = selection;
    state = AsyncData(selection);
  }
}

/// Zaghlol shows his still pose, so the page settles (no looping animation).
class StillMascot extends ReduceMotionNotifier {
  @override
  bool build() => true;
}

/// Opens "All charts (12)" so the charts behind it are built.
Future<void> openAllCharts(WidgetTester tester) async {
  final button = find.byKey(const Key('charts-all'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The summary strip's figures in tests: spent 1,980 (vs 2,150), income
/// 3,200 (same), as in the PO mockup but in whole pounds.
ChartSummary summaryData() => ChartSummary.compute(
  PeriodTotals(income: egpM(32000), spend: egpM(19800)),
  PeriodTotals(income: egpM(32000), spend: egpM(21500)),
);

/// The default view: six months of cycle points (T-188 keeps the trend).
List<CashFlowPoint> cashFlowPoints() => [
  for (var m = 5; m <= 10; m++)
    CashFlowPoint(
      period: ChartPeriod.month(2026, m),
      income: egpM(30000),
      spend: egpM(18000 + m * 500),
      isPartial: false,
    ),
];

/// One point per day (17 days of a month period).
List<CashFlowPoint> dailyCashFlowPoints() => [
  for (var i = 0; i < 17; i++)
    CashFlowPoint(
      period: ChartPeriod(
        CivilDate(2026, 10, 25).plusDays(i),
        CivilDate(2026, 10, 25).plusDays(i),
      ),
      income: egpM(i == 0 ? 30000 : 0),
      spend: egpM(600 + i * 50),
      isPartial: false,
    ),
];

/// Six months of weekly points (26 weeks to 10 Nov 2026), the "last 6
/// months" view.
List<CashFlowPoint> weeklyCashFlowPoints() => [
  for (var i = 0; i < 24; i++)
    CashFlowPoint(
      period: ChartPeriod(
        CivilDate(2026, 6, 1).plusDays(i * 7),
        CivilDate(2026, 6, 1).plusDays(i * 7 + 6),
      ),
      income: egpM(i % 4 == 0 ? 30000 : 1000),
      spend: egpM(4000 + (i * 7919) % 3000),
      isPartial: false,
    ),
];

CategoryDonut donutData() => CategoryDonut(
  total: egpM(1000),
  slices: [
    CategorySlice(categoryId: null, amount: egpM(600), shareBp: 6000, count: 5),
    CategorySlice(categoryId: 'x', amount: egpM(400), shareBp: 4000, count: 3),
  ],
);

List<MerchantSpend> merchants(int n) => [
  for (var i = 0; i < n; i++)
    MerchantSpend(
      merchantNorm: 'm$i',
      name: 'Shop $i',
      amount: egpM(1000 - i * 100),
      count: 2,
    ),
];

List<Override> chartOverrides({
  List<Currency>? currencies,
  ChartResult<List<CashFlowPoint>>? cashFlow,
  ChartResult<CategoryDonut>? donut,
  ChartResult<List<MerchantSpend>>? top,
  bool cashFlowError = false,
  bool loading = false,
  ChartPeriodSelection selection = ChartPeriodSelection.thisCycle,
  ChartSummary? summary,
  CategoryDonut? previousDonut,
  void Function(String code)? onSummary,
  ({Money amount, int count}) Function(DrillScope scope)? drillTotals,
  List<CategoryRow> categories = const [],
}) {
  final cur = currencies ?? [egp];
  return [
    chartsCurrenciesProvider.overrideWith((ref) async => cur),
    categoryRowsProvider.overrideWith((ref) async => categories),
    budgetScreenDataProvider.overrideWith(
      (ref) async => data([egpView(), usdView()]),
    ),
    cashFlowChartProvider.overrideWith((ref, code) async {
      if (cashFlowError) throw StateError('boom');
      return cashFlow ?? ChartReady(cashFlowPoints());
    }),
    cashFlowTotalProvider.overrideWith((ref, code) async {
      final r = cashFlow ?? ChartReady(cashFlowPoints());
      return switch (r) {
        ChartReady(:final data) => ChartReady([CashFlowPoint.total(data)]),
        ChartNotEnoughData() => r,
      };
    }),
    previousCashFlowTotalProvider.overrideWith(
      (ref, code) async => ChartReady([CashFlowPoint.total(cashFlowPoints())]),
    ),
    donutChartProvider.overrideWith(
      (ref, code) async => donut ?? ChartReady(donutData()),
    ),
    chartSummaryProvider.overrideWith((ref, code) async {
      onSummary?.call(code);
      return summary ?? summaryData();
    }),
    previousDonutProvider.overrideWith((ref, code) async => previousDonut),
    drillTotalsProvider.overrideWith(
      (ref, scope) async =>
          drillTotals?.call(scope) ?? (amount: egpM(5400), count: 23),
    ),
    merchantsChartProvider.overrideWith(
      (ref, code) async => top ?? ChartReady(merchants(5)),
    ),
    todayProvider.overrideWith(ChartsFixedToday.new),
    paydayScheduleProvider.overrideWith(
      (ref) async => PaydaySchedule.single(25),
    ),
    chartPeriodSelectionProvider.overrideWith(
      () => FakeChartPeriodSelection(selection),
    ),
    reduceMotionProvider.overrideWith(StillMascot.new),
  ];
}

// ---------------------------------------------------------- T-114 Gold data

Money _egp(int major) => Money(egp, major * 100);

BurnCurve burnData() => BurnCurve(
  cycle: Cycle(start: CivilDate(2026, 10, 25), end: CivilDate(2026, 11, 24)),
  elapsedDays: 5,
  cumulative: [for (var i = 1; i <= 5; i++) _egp(i * 300)],
  budget: _egp(22000),
  projectedTotal: _egp(9300),
);

FiftyThirtyTwenty ruleData() => FiftyThirtyTwenty(
  income: _egp(30000),
  needs: _egp(16000),
  wants: _egp(8000),
  savings: _egp(6000),
  other: _egp(0),
);

DayHourPattern dayHourData() => DayHourPattern(
  byWeekday: {
    for (var d = 1; d <= 7; d++) d: DayHourCell(spend: _egp(d * 100), count: d),
  },
  byHour: {
    for (var h = 0; h < 24; h++) h: DayHourCell(spend: _egp(h), count: 1),
  },
);

MonthVsAverage vsAverageData() => MonthVsAverage(
  current: _egp(9000),
  average: _egp(8000),
  deltaBp: 1250,
  cyclesCounted: 3,
  elapsedDays: 15,
  byCategory: [
    CategoryComparison(
      categoryId: 'x',
      current: _egp(3000),
      average: _egp(2000),
      deltaBp: 5000,
    ),
  ],
);

List<InstallmentMonth> installmentData() => [
  for (var m = 11; m <= 12; m++)
    InstallmentMonth(year: 2026, month: m, total: _egp(1500), dues: const []),
];

SubscriptionsAnnual subscriptionsData() => SubscriptionsAnnual(
  items: [
    SubscriptionCost(
      itemId: 's1',
      name: 'Streamly',
      amount: _egp(100),
      annual: _egp(1200),
    ),
  ],
  annualTotal: _egp(1200),
);

List<CardSpend> cardsData() => [
  CardSpend(
    accountId: 'a1',
    label: 'Visa 1234',
    kind: 'credit',
    spend: _egp(700),
    shareBp: 7000,
    count: 4,
  ),
  CardSpend(
    accountId: 'a2',
    label: 'Wallet',
    kind: 'wallet',
    spend: _egp(300),
    shareBp: 3000,
    count: 2,
  ),
];

List<NetWorthPoint> netWorthData() => [
  for (var i = 0; i < 4; i++)
    NetWorthPoint(
      takenOn: CivilDate(2026, 7 + i, 1),
      unit: 'EGP',
      assetsMinor: (10000 + i * 1000) * 100,
      liabilitiesMinor: 2000 * 100,
    ),
];

List<InflationPoint> inflationData() => [
  for (var i = 0; i < 4; i++)
    InflationPoint(
      year: 2026,
      month: 7 + i,
      indexBp: 10000 + i * 200,
      merchants: 4,
    ),
];

/// Overrides for the nine Gold charts. [empty] makes each say "not enough".
List<Override> goldChartOverrides({
  bool empty = false,
  bool error = false,
  ChartResult<List<NetWorthPoint>>? netWorth,
  void Function()? onBurn,
}) {
  ChartResult<T> r<T>(T v) => empty
      ? ChartNotEnoughData<T>(NotEnoughReason.noData, have: 0, need: 1)
      : ChartReady<T>(v);
  Future<ChartResult<T>> f<T>(T v) async {
    if (error) throw StateError('boom');
    return r(v);
  }

  return [
    burnChartProvider.overrideWith((ref, c) {
      onBurn?.call();
      return f(burnData());
    }),
    rule503020ChartProvider.overrideWith((ref, c) => f(ruleData())),
    dayHourChartProvider.overrideWith((ref, c) => f(dayHourData())),
    vsAverageChartProvider.overrideWith((ref, c) => f(vsAverageData())),
    installmentsChartProvider.overrideWith((ref, c) => f(installmentData())),
    subscriptionsChartProvider.overrideWith((ref, c) => f(subscriptionsData())),
    cardsChartProvider.overrideWith((ref, c) => f(cardsData())),
    netWorthChartProvider.overrideWith(
      (ref, c) async => netWorth ?? await f(netWorthData()),
    ),
    inflationChartProvider.overrideWith((ref, c) => f(inflationData())),
  ];
}
