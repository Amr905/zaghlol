// T-114: the nine Gold chart cards on S-20 and S-21. Synthetic data only.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/charts/gold_chart_card.dart';
import 'package:zaghlol/features/insights/presentation/charts/locked_chart_card.dart';

import 'charts_test_support.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = _en,
  double scale = 1.0,
  bool gold = true,
  List<Override>? overrides,
}) async {
  await initDateFormatting();
  await tester.pumpWidget(const SizedBox());
  await tester.binding.setSurfaceSize(const Size(390, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      child,
      locale: locale,
      scale: scale,
      overrides: overrides ?? [...chartOverrides(), ...goldChartOverrides()],
    ),
  );
  if (gold) {
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
  }
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester t, Type root) =>
    AppLocalizations.of(t.element(find.byType(root)));

void main() {
  for (final locale in const [_en, _ar]) {
    final tag = locale.languageCode;

    testWidgets('$tag: Gold sees nine real charts, no locked previews', (
      tester,
    ) async {
      await _pump(tester, const ChartsScreen(), locale: locale);
      final l = _l(tester, ChartsScreen);
      expect(find.byType(LockedChartCard, skipOffstage: false), findsNothing);
      expect(find.byType(GoldChartCard, skipOffstage: false), findsNWidgets(9));
      for (final t in [
        l.insightsChartTitleBurnRate,
        l.insightsChartTitleRule503020,
        l.insightsChartTitleWeekPattern,
        l.insightsChartTitleVsAverage,
        l.insightsChartTitleInstallments,
        l.insightsChartTitleSubscriptions,
        l.insightsChartTitleCards,
        l.insightsChartTitleNetWorth,
        l.insightsChartTitleInflation,
      ]) {
        expect(find.text(t, skipOffstage: false), findsWidgets);
      }
      expect(
        find.byType(LineChart, skipOffstage: false),
        findsNWidgets(3), // burn, net worth, inflation
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('$tag: Free keeps nine locked previews', (tester) async {
      await _pump(tester, const ChartsScreen(), locale: locale, gold: false);
      expect(
        find.byType(LockedChartCard, skipOffstage: false),
        findsNWidgets(9),
      );
      expect(find.byType(GoldChartCard, skipOffstage: false), findsNothing);
    });

    testWidgets('$tag: empty and error states per chart', (tester) async {
      for (final id in goldChartIds) {
        await _pump(
          tester,
          GoldChartCard(chart: id, code: 'EGP'),
          locale: locale,
          overrides: [...chartOverrides(), ...goldChartOverrides(empty: true)],
        );
        final l = _l(tester, GoldChartCard);
        expect(
          find.text(
            id == ChartId.netWorth
                ? l.insightsChartsEmptyNetWorth
                : l.insightsChartsEmptyFilter,
          ),
          findsOneWidget,
          reason: '$id empty',
        );
        await _pump(
          tester,
          GoldChartCard(chart: id, code: 'EGP'),
          locale: locale,
          overrides: [...chartOverrides(), ...goldChartOverrides(error: true)],
        );
        expect(
          find.text(_l(tester, GoldChartCard).insightsChartsCardError),
          findsOneWidget,
          reason: '$id error',
        );
      }
    });

    testWidgets('$tag: text scale 1.3 does not overflow', (tester) async {
      await _pump(tester, const ChartsScreen(), locale: locale, scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RTL reverses bar order, LTR does not', (tester) async {
    Future<List<double>> ys(Locale locale) async {
      await _pump(
        tester,
        const GoldChartCard(chart: ChartId.installmentTimeline, code: 'EGP'),
        locale: locale,
        overrides: [
          ...chartOverrides(),
          installmentsChartProvider.overrideWith(
            (ref, c) async => ChartReady([
              InstallmentMonth(
                year: 2026,
                month: 11,
                total: egpM(100),
                dues: const [],
              ),
              InstallmentMonth(
                year: 2026,
                month: 12,
                total: egpM(900),
                dues: const [],
              ),
            ]),
          ),
        ],
      );
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      return [for (final g in chart.data.barGroups) g.barRods.first.toY];
    }

    expect(await ys(_en), [10000.0, 90000.0]);
    expect(await ys(_ar), [90000.0, 10000.0]);
  });

  testWidgets('cards rows open S-41 only when the shell wires it', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      const GoldChartCard(chart: ChartId.cardsSplit, code: 'EGP'),
      overrides: [
        ...chartOverrides(),
        ...goldChartOverrides(),
        chartCardOpenerProvider.overrideWithValue((_, id) => opened = id),
      ],
    );
    await tester.tap(find.text('Visa 1234'));
    expect(opened, 'a1');
  });

  testWidgets('a11y summaries carry the figures', (tester) async {
    await _pump(tester, const ChartsScreen());
    expect(find.bySemanticsLabel(RegExp(r'^Subscriptions')), findsWidgets);
  });

  testWidgets('S-21 draws a Gold chart in detail (not "needs data")', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChartDetailScreen(chart: ChartId.cardsSplit, code: 'EGP'),
    );
    expect(find.text('Visa 1234'), findsOneWidget);
    expect(find.byType(GoldChartCard), findsOneWidget);
  });

  testWidgets('S-21 explainer works for a wired Gold chart', (tester) async {
    await _pump(
      tester,
      const ChartDetailScreen(
        chart: ChartId.fiftyThirtyTwenty,
        code: 'EGP',
        openExplainer: true,
      ),
      overrides: [
        ...chartOverrides(),
        ...goldChartOverrides(),
        essentialCategoryIdsProvider.overrideWith((ref) async => {'a'}),
        previousRule503020ChartProvider.overrideWith(
          (ref, c) async => ChartReady(ruleData()),
        ),
      ],
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final l = _l(tester, ChartDetailScreen);
    expect(find.text(l.insightsChartDetailExplainFailed), findsNothing);
    expect(find.byKey(const ValueKey('explainer-bubble')), findsOneWidget);
  });
}
