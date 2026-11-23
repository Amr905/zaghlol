import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_bodies.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_card.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/charts/locked_chart_card.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/insights/presentation/v2/insights_v2_screen.dart';

import 'charts_test_support.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  double scale = 1.0,
  List<Override>? overrides,
  bool openAll = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      const ChartsScreen(),
      locale: locale,
      scale: scale,
      overrides: [
        ...(overrides ?? chartOverrides()),
        if (!openAll) chartsOpenToFreeProvider.overrideWithValue(false),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ChartsScreen)));

void main() {
  // CHARTS-FREE: these tests cover the Gold gate itself, so close it.

  for (final locale in const [_en, _ar]) {
    final tag = locale.languageCode;
    testWidgets('$tag: four free charts render, nine locked previews', (
      tester,
    ) async {
      await _pump(tester, locale: locale);
      final l = _l(tester);
      expect(find.text(l.insightsChartTitleCashFlow), findsOneWidget);
      expect(find.text(l.insightsChartTitleCategories), findsOneWidget);
      expect(find.text(l.insightsChartTitleMerchants), findsOneWidget);
      expect(find.text(l.insightsTabsBudget), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
      // Month vs average is the one locked chart in the main list.
      expect(find.byType(LockedChartCard, skipOffstage: false), findsOneWidget);
      await openAllCharts(tester);
      await tester.scrollUntilVisible(
        find.text(l.insightsChartTitleInflation),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byType(LockedChartCard, skipOffstage: false),
        findsNWidgets(9),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$tag: text scale 1.3 does not overflow', (tester) async {
      await _pump(tester, locale: locale, scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('free: top merchants shows 5 rows', (tester) async {
    await _pump(tester);
    expect(find.text('Shop 4'), findsOneWidget);
    expect(find.text('Shop 5'), findsNothing);
  });

  testWidgets('locked previews hold no numbers and CTA opens paywall', (
    tester,
  ) async {
    GoldCapability? hit;
    await _pump(
      tester,
      overrides: [
        ...chartOverrides(),
        paywallTriggerProvider.overrideWithValue((c) => hit = c),
      ],
    );
    await openAllCharts(tester);
    final l = _l(tester);
    final cards = find.byType(LockedChartCard, skipOffstage: false);
    expect(
      find.descendant(
        of: cards,
        matching: find.byWidgetPredicate(
          (w) => w is BarChart || w is PieChart || w is LineChart,
          skipOffstage: false,
        ),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: cards,
        matching: find.textContaining('EGP', skipOffstage: false),
        skipOffstage: false,
      ),
      findsNothing,
    );
    final cta = find.text(l.commonGoldUnlock, skipOffstage: false).first;
    await tester.scrollUntilVisible(
      cta,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(cta);
    expect(hit, GoldCapability.allCharts);
  });

  testWidgets('a11y summary labels carry the figures', (tester) async {
    await _pump(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'^Top merchants: Shop 0 first')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Cash flow: income')),
      findsOneWidget,
    );
  });

  testWidgets('RTL reverses cash flow bars so time runs right to left', (
    tester,
  ) async {
    await _pump(tester, locale: _ar);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final first = chart.data.barGroups.first.barRods[1].toY;
    // Oldest bucket (smallest spend) is last in RTL data order.
    expect(chart.data.barGroups.last.barRods[1].toY < first, isTrue);
    await _pump(tester, locale: _en);
    final en = tester.widget<BarChart>(find.byType(BarChart));
    expect(
      en.data.barGroups.first.barRods[1].toY <
          en.data.barGroups.last.barRods[1].toY,
      isTrue,
    );
  });

  testWidgets(
    'period chip shows the resolved range; the sheet picks a preset',
    (tester) async {
      await _pump(tester);
      expect(find.text('Oct 25 – Nov 24'), findsOneWidget);
      await tester.tap(find.byKey(const Key('charts-period')));
      await tester.pumpAndSettle();
      final l = _l(tester);
      // The payday cycle reads "month" (PO sign-off); the calendar months
      // keep their own rows, told apart by their ranges.
      expect(find.text(l.insightsChartsPresetThisCycle), findsNWidgets(2));
      expect(find.text(l.insightsChartsPresetLastCycle), findsNWidgets(2));
      expect(find.textContaining('cycle'), findsNothing);
      for (final name in [l.commonPeriodThisYear, l.commonPeriodCustom]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      await tester.tap(find.byKey(const Key('charts-period-last6Months')));
      await tester.pumpAndSettle();
      expect(
        FakeChartPeriodSelection.last,
        const ChartPeriodSelection(ChartPreset.last6Months),
      );
      expect(find.text('Jun 1 – Nov 10'), findsOneWidget);
    },
  );

  testWidgets('previous / next step the period and next stops at today', (
    tester,
  ) async {
    FakeChartPeriodSelection.last = null;
    await _pump(tester);
    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(Key(key)));
    expect(button('charts-period-next').onPressed, isNull);
    await tester.tap(find.byKey(const Key('charts-period-prev')));
    await tester.pumpAndSettle();
    expect(find.text('Sep 25 – Oct 24'), findsOneWidget);
    expect(button('charts-period-next').onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('charts-period-next')));
    await tester.pumpAndSettle();
    expect(find.text('Oct 25 – Nov 24'), findsOneWidget);
    expect(button('charts-period-next').onPressed, isNull);
  });

  testWidgets('RTL: previous sits on the right, the chevrons mirror', (
    tester,
  ) async {
    await _pump(tester, locale: _ar);
    final prev = tester.getCenter(find.byKey(const Key('charts-period-prev')));
    final next = tester.getCenter(find.byKey(const Key('charts-period-next')));
    expect(prev.dx, greaterThan(next.dx));
    expect(
      tester.getSize(find.byKey(const Key('charts-period-prev'))).shortestSide,
      greaterThanOrEqualTo(44),
    );
    // Arabic digits in the range, Gregorian month names.
    expect(find.textContaining('٢٥'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom range from the picker is clamped and applied', (
    tester,
  ) async {
    FakeChartPeriodSelection.last = null;
    await _pump(tester);
    await tester.tap(find.byKey(const Key('charts-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('charts-period-custom')));
    await tester.pumpAndSettle();
    // The Material range picker opens; confirm its default range.
    await tester.tap(find.text(_l(tester).commonActionDone));
    await tester.pumpAndSettle();
    final s = FakeChartPeriodSelection.last!;
    expect(s.preset, ChartPreset.custom);
    expect(s.customFrom, CivilDate(2026, 10, 25));
    // This cycle ends on 24 Nov, after today: the picker opens cut at today.
    expect(s.customTo, chartsToday);
  });

  testWidgets('default: six cycles, caption says so, three rods per bar', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.text('Last 6 months · this month is not over yet'),
      findsOneWidget,
    );
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups, hasLength(6));
    // Income and spent per bar; saved lives in the summary strip.
    expect(chart.data.barGroups.first.barRods, hasLength(2));
    // The open (current) month is hatched: a dashed outline.
    expect(chart.data.barGroups.last.barRods.first.borderDashArray, isNotNull);
    expect(chart.data.barGroups.first.barRods.first.borderDashArray, isNull);
  });

  testWidgets('cash flow caption and bars follow the bucket size', (
    tester,
  ) async {
    // One cycle: day buckets.
    final days = [
      for (var i = 0; i < 17; i++)
        CashFlowPoint(
          period: ChartPeriod(
            CivilDate(2026, 10, 25).plusDays(i),
            CivilDate(2026, 10, 25).plusDays(i),
          ),
          income: egpM(i == 0 ? 30000 : 0),
          spend: egpM(100 + i),
          isPartial: false,
        ),
    ];
    await _pump(
      tester,
      overrides: chartOverrides(
        cashFlow: ChartReady(days),
        selection: const ChartPeriodSelection(ChartPreset.thisMonth),
      ),
    );
    expect(find.textContaining('17 days'), findsOneWidget);
    // Month cue on the first bar and on day 1 (F7).
    expect(find.text('Oct 25'), findsOneWidget);
    expect(find.text('Nov 1'), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    // Dense: income and spent only.
    expect(chart.data.barGroups.first.barRods, hasLength(2));
    expect(
      find.descendant(
        of: find.byType(CashFlowBody),
        matching: find.text('Saved'),
      ),
      findsNothing,
    );
  });

  testWidgets('cycle-only charts say so for a month period', (tester) async {
    await _pump(
      tester,
      openAll: true,
      overrides: [
        ...chartOverrides(
          selection: const ChartPeriodSelection(ChartPreset.thisMonth),
        ),
        ...goldChartOverrides(),
      ],
    );
    await tester.scrollUntilVisible(
      find.text(_l(tester).insightsChartTitleVsAverage),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await openAllCharts(tester);
    expect(
      find.text(_l(tester).insightsChartsPeriodNeedsCycle),
      findsNWidgets(2),
    );
    // The budget card says it shows the current cycle.
    expect(
      find.text(_l(tester).insightsChartsPeriodBudgetNote, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('currency chips switch currency', (tester) async {
    await _pump(tester, overrides: chartOverrides(currencies: [egp, usd]));
    expect(find.text('USD'), findsOneWidget);
    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    expect(find.textContaining('USD'), findsWidgets);
  });

  testWidgets('empty: no activity and not-enough-data variants', (
    tester,
  ) async {
    await _pump(tester, overrides: chartOverrides(currencies: []));
    expect(find.text(_l(tester).insightsChartsEmptyCycle), findsOneWidget);
    expect(find.text(_l(tester).insightsThinNoData), findsNWidgets(2));
  });

  testWidgets('empty: not-enough-data variants name the reason', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: chartOverrides(
        cashFlow: const ChartNotEnoughData(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        ),
        donut: const ChartNotEnoughData(
          NotEnoughReason.tooFewTransactions,
          have: 1,
          need: 3,
        ),
      ),
    );
    final l = _l(tester);
    expect(find.text(l.insightsChartsEmptyFilter), findsOneWidget);
    // Below a chart's minimum, Zaghlol says how much is missing.
    expect(find.text(l.insightsThinNeedTxns(2, '2')), findsOneWidget);
  });

  testWidgets('error: one chart fails, others stay', (tester) async {
    await _pump(tester, overrides: chartOverrides(cashFlowError: true));
    final l = _l(tester);
    expect(find.text(l.insightsChartsCardError), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text(l.commonActionTryAgain), findsOneWidget);
  });

  testWidgets('loading shows skeletons with a11y label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const ChartsScreen(),
        locale: _en,
        overrides: [
          ...chartOverrides().skip(1),
          chartsCurrenciesProvider.overrideWith(
            (ref) => Future<List<Currency>>.delayed(
              const Duration(seconds: 1),
              () => [egp],
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(ChartSkeleton), findsWidgets);
    expect(find.byKey(const Key('charts-period')), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ChartSkeleton).first).label,
      contains('Loading charts'),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    handle.dispose();
  });

  testWidgets('Insights shell plugs in the charts segment (v2 Overview; the '
      'T-189 screen sits behind All charts)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(const InsightsScreen(), locale: _en, overrides: chartOverrides()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChartsV2Screen), findsOneWidget);
    expect(find.byType(ChartsScreen), findsNothing);
  });
}
