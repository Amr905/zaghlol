// T-211: widget tests of the v2 Trends tab, one per state. AC map in
// docs/04-tasks/tasks/T-211.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/insights/presentation/charts/locked_chart_card.dart';
import 'package:zaghlol/features/insights/presentation/v2/heatmap_card.dart';
import 'package:zaghlol/features/insights/presentation/v2/trends_tab.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../support/hide_amounts_support.dart';
import 'trends_test_support.dart';

const _en = Locale('en');
const _ar = Locale('ar', 'EG');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  List<Override>? overrides,
  HideAmountsHarness? hidden,
  double scale = 1.0,
  bool dark = false,
  bool closeGate = false,
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 2100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      const TrendsTab(),
      locale: locale,
      scale: scale,
      dark: dark,
      hideAmounts: hidden,
      overrides: [
        ...(overrides ?? trendsOverrides()),
        if (closeGate) chartsOpenToFreeProvider.overrideWithValue(false),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Finder _ink(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(Ink));

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(TrendsTab)));

void main() {
  for (final locale in const [_en, _ar]) {
    final tag = locale.languageCode;

    testWidgets('$tag: populated, 1.3x text scale, no overflow', (
      tester,
    ) async {
      await _pump(tester, locale: locale, scale: 1.3);
      final l = _l(tester);
      expect(find.text(l.insightsV2TrendsInOutTitle), findsOneWidget);
      expect(find.text(l.insightsV2SavedTitle), findsOneWidget);
      expect(find.text(l.insightsV2TrendsDayTitle), findsOneWidget);
      expect(find.text(l.insightsV2TrendsLegendSpent), findsOneWidget);
      expect(find.text(l.insightsV2TrendsLegendProjected), findsOneWidget);
      expect(find.text(l.insightsV2TrendsDayLess), findsOneWidget);
      expect(find.text(l.insightsV2TrendsDayMore), findsOneWidget);
      expect(find.byKey(const Key('heat-priciest')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('heatmap RTL mirrors: the first day sits at the end side', (
    tester,
  ) async {
    await _pump(tester, locale: _en);
    final ltr = tester.getCenter(find.byKey(const Key('heat-2026-10-25')));
    await _pump(tester, locale: _ar);
    final rtl = tester.getCenter(find.byKey(const Key('heat-2026-10-25')));
    // 25 Oct is the second cell of the week row (Saturday first).
    expect(ltr.dx, lessThan(195));
    expect(rtl.dx, greaterThan(195));
  });

  testWidgets('week starts Saturday: first header is Sat', (tester) async {
    await _pump(tester);
    expect(find.text('Sat'), findsOneWidget);
    final sat = tester.getTopLeft(find.text('Sat')).dx;
    final fri = tester.getTopLeft(find.text('Fri')).dx;
    expect(sat, lessThan(fri));
  });

  testWidgets('future days are outlined (not filled); today has a ring', (
    tester,
  ) async {
    await _pump(tester);
    final future = tester.widget<DecoratedBox>(
      find.byKey(const Key('heat-2026-11-20')),
    );
    final d = future.decoration as BoxDecoration;
    expect(d.color, isNull);
    expect(d.border, isNotNull);
    final today = tester.widget<Ink>(_ink('heat-2026-11-10'));
    expect((today.decoration as BoxDecoration).border, isNotNull);
  });

  testWidgets('a zero day is the lightest cell', (tester) async {
    await _pump(tester);
    final zero = tester.widget<Ink>(_ink('heat-2026-10-27'));
    final c = ZColorsProbe.light;
    expect((zero.decoration as BoxDecoration).color, heatColor(c, 0));
  });

  testWidgets('tapping a day opens that day\'s transactions', (tester) async {
    await _pump(tester);
    final cell = find.byKey(const Key('heat-2026-10-26'));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      Navigator.of(tester.element(find.byType(TrendsTab))).canPop(),
      isTrue,
    );
  });

  testWidgets('priciest caption is omitted under two weeks of data', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: trendsOverrides(today: CivilDate(2026, 11, 3)),
    );
    expect(find.byKey(const Key('heat-priciest')), findsNothing);
  });

  testWidgets('empty month: no bar is drawn for it, a11y says no data', (
    tester,
  ) async {
    await _pump(tester, overrides: trendsOverrides(emptyFirstMonth: true));
    final l = _l(tester);
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(l.insightsV2TrendsInOutEmptyA11y('Jun'))),
      ),
      findsOneWidget,
    );
  });

  testWidgets('loading state shows skeletons', (tester) async {
    await initDateFormatting();
    await tester.binding.setSurfaceSize(const Size(390, 2100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const TrendsTab(),
        locale: _en,
        overrides: trendsOverrides(loading: true),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(HeatmapCard), findsOneWidget);
    expect(find.byType(InOutCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state offers a retry', (tester) async {
    await _pump(tester, overrides: trendsOverrides(error: true));
    final l = _l(tester);
    expect(find.text(l.insightsV2TrendsInOutTitle), findsOneWidget);
    expect(find.text(l.insightsV2TrendsDayTitle), findsOneWidget);
    expect(find.text(l.commonActionTryAgain), findsWidgets);
  });

  testWidgets('no spending: the heatmap says there is nothing yet', (
    tester,
  ) async {
    await _pump(tester, overrides: trendsOverrides(noSpend: true));
    final l = _l(tester);
    expect(find.text(l.insightsChartsEmptyCycle), findsWidgets);
  });

  testWidgets('hide amounts masks the semantics labels', (tester) async {
    await _pump(tester, hidden: HideAmountsHarness(hidden: true));
    final l = _l(tester);
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(l.commonAmountHidden))),
      findsWidgets,
    );
    expect(find.textContaining('****'), findsNothing);
  });

  testWidgets('free user sees the locked cards when charts are Gold', (
    tester,
  ) async {
    await _pump(tester, closeGate: true);
    expect(find.byType(HeatmapCard), findsNothing);
    expect(find.byType(InOutCard), findsOneWidget);
    // The heatmap's locked card carries its own title (T-218).
    final l = AppLocalizations.of(tester.element(find.byType(TrendsTab)));
    expect(
      find.descendant(
        of: find.byType(LockedChartCard),
        matching: find.text(l.insightsV2TrendsDayTitle),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dark theme builds', (tester) async {
    await _pump(tester, dark: true);
    expect(tester.takeException(), isNull);
  });
}
