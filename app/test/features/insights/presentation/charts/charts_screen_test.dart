import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_card.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/charts/locked_chart_card.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';

import 'charts_test_support.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  double scale = 1.0,
  List<Override>? overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      const ChartsScreen(),
      locale: locale,
      scale: scale,
      overrides: overrides ?? chartOverrides(),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ChartsScreen)));

void main() {
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
    expect(find.text(_l(tester).insightsChartsEmptyCycle), findsNWidgets(3));
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
    expect(find.text(l.insightsChartsEmptyCycle), findsOneWidget);
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
    expect(
      tester.getSemantics(find.byType(ChartSkeleton).first).label,
      contains('Loading charts'),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    handle.dispose();
  });

  testWidgets('Insights shell plugs in the charts segment', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(const InsightsScreen(), locale: _en, overrides: chartOverrides()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChartsScreen), findsOneWidget);
  });
}
