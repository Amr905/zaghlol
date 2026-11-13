// T-108: S-21 chart detail & explanation, every state in ar + en.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import 'charts/charts_test_support.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

CategoryDonut _donut() => CategoryDonut(
  total: egpM(1000),
  slices: [
    CategorySlice(categoryId: 'a', amount: egpM(500), shareBp: 5000, count: 5),
    CategorySlice(categoryId: 'b', amount: egpM(300), shareBp: 3000, count: 3),
    CategorySlice(categoryId: 'c', amount: egpM(200), shareBp: 2000, count: 2),
  ],
);

List<Override> _overrides({
  ChartResult<CategoryDonut>? donut,
  bool explainError = false,
}) => [
  ...chartOverrides(donut: donut ?? ChartReady(_donut())),
  previousDonutChartProvider.overrideWith(
    (ref, code) async => ChartReady(
      CategoryDonut(
        total: egpM(900),
        slices: [
          CategorySlice(
            categoryId: 'a',
            amount: egpM(400),
            shareBp: 4400,
            count: 4,
          ),
          CategorySlice(
            categoryId: 'b',
            amount: egpM(300),
            shareBp: 3300,
            count: 3,
          ),
        ],
      ),
    ),
  ),
  if (explainError)
    chartExplanationProvider.overrideWith(
      (ref, key) async => throw StateError('boom'),
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  ChartId chart = ChartId.categoryDonut,
  Locale locale = _en,
  double scale = 1.0,
  bool open = false,
  bool gold = false,
  List<Override>? overrides,
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      ChartDetailScreen(chart: chart, code: 'EGP', openExplainer: open),
      locale: locale,
      scale: scale,
      overrides: overrides ?? _overrides(),
    ),
  );
  if (gold) {
    ProviderScope.containerOf(tester.element(find.byType(ChartDetailScreen)))
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
  }
  await tester.pump();
  await tester.pump();
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ChartDetailScreen)));

Future<void> _typed(WidgetTester t) async {
  await t.pump(chartTypingDuration + const Duration(milliseconds: 50));
  await t.pump();
}

void main() {
  for (final locale in const [_en, _ar]) {
    final tag = locale.languageCode;

    testWidgets('$tag: closed explainer shows the button, not the text', (
      tester,
    ) async {
      await _pump(tester, locale: locale);
      final l = _l(tester);
      expect(find.text(l.insightsChartsExplain), findsOneWidget);
      expect(find.byKey(const ValueKey('explainer-bubble')), findsOneWidget);
      expect(find.text(l.insightsChartDetailTipLabel), findsNothing);
      expect(find.byType(ZaghlolAvatar), findsOneWidget);
      expect(
        tester.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar)).moment,
        ZaghlolMoment.professor,
      );
    });

    testWidgets('$tag: free sees fact + tip + deep upsell, no deep lines', (
      tester,
    ) async {
      GoldCapability? hit;
      await _pump(
        tester,
        locale: locale,
        open: true,
        overrides: [
          ..._overrides(),
          paywallTriggerProvider.overrideWithValue((c) => hit = c),
        ],
      );
      final l = _l(tester);
      // Typing first.
      expect(
        find.bySemanticsLabel(l.insightsChartDetailTypingA11y),
        findsOneWidget,
      );
      await _typed(tester);
      expect(find.text(l.insightsChartDetailTipLabel), findsOneWidget);
      expect(find.text(l.insightsChartDetailDeepLabel), findsNothing);
      expect(find.text(l.insightsChartDetailDeepUpsell), findsOneWidget);
      await tester.tap(find.text(l.commonGoldUnlock));
      expect(hit, GoldCapability.deepCoaching);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$tag: gold sees the deep tier, no upsell', (tester) async {
      await _pump(tester, locale: locale, open: true, gold: true);
      final l = _l(tester);
      await _typed(tester);
      await tester.pump();
      expect(find.text(l.insightsChartDetailDeepLabel), findsWidgets);
      expect(find.text(l.insightsChartDetailDeepUpsell), findsNothing);
    });

    testWidgets('$tag: not enough data says what is needed', (tester) async {
      await _pump(
        tester,
        locale: locale,
        open: true,
        overrides: _overrides(
          donut: const ChartNotEnoughData(
            NotEnoughReason.tooFewTransactions,
            have: 1,
            need: 5,
          ),
        ),
      );
      await _typed(tester);
      expect(
        find.text(_l(tester).insightsChartDetailNeedsData('cycle')),
        findsOneWidget,
      );
    });

    testWidgets('$tag: explainer failure hides the bubble, chart stays', (
      tester,
    ) async {
      await _pump(
        tester,
        locale: locale,
        open: true,
        overrides: _overrides(explainError: true),
      );
      await _typed(tester);
      final l = _l(tester);
      expect(find.text(l.insightsChartDetailExplainFailed), findsOneWidget);
      expect(find.byKey(const ValueKey('explainer-bubble')), findsNothing);
      expect(find.text(l.insightsChartTitleCategories), findsWidgets);
    });

    testWidgets('$tag: Gold chart is locked for Free, CTA opens paywall', (
      tester,
    ) async {
      GoldCapability? hit;
      await _pump(
        tester,
        chart: ChartId.burnCurve,
        locale: locale,
        overrides: [
          ..._overrides(),
          paywallTriggerProvider.overrideWithValue((c) => hit = c),
        ],
      );
      final l = _l(tester);
      expect(find.text(l.insightsChartDetailLockedTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('explainer-bubble')), findsNothing);
      await tester.tap(find.text(l.commonGoldUnlock));
      expect(hit, GoldCapability.allCharts);
    });

    testWidgets('$tag: text scale 1.3 does not overflow', (tester) async {
      await _pump(tester, locale: locale, scale: 1.3, open: true);
      await _typed(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('typing indicator lasts at most 600 ms', (tester) async {
    await _pump(tester, open: true);
    final l = _l(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(
      find.bySemanticsLabel(l.insightsChartDetailTypingA11y),
      findsNothing,
    );
  });

  testWidgets('tapping Explain opens the explainer', (tester) async {
    await _pump(tester);
    final l = _l(tester);
    await tester.tap(find.text(l.insightsChartsExplain));
    await tester.pump();
    expect(
      find.bySemanticsLabel(l.insightsChartDetailTypingA11y),
      findsOneWidget,
    );
    await _typed(tester);
    expect(find.text(l.insightsChartDetailTipLabel), findsOneWidget);
  });

  testWidgets('essential categories are never the tip target (Q-25)', (
    tester,
  ) async {
    // Category 'a' (largest) is essential; the tip must name 'b' instead.
    await _pump(
      tester,
      open: true,
      overrides: [
        ..._overrides(),
        essentialCategoryIdsProvider.overrideWith((ref) async => {'a'}),
      ],
    );
    await _typed(tester);
    final key = (chart: ChartId.categoryDonut, code: 'EGP');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChartDetailScreen)),
    );
    final lines = container
        .read(chartExplanationProvider(key))
        .requireValue
        .explanation
        .lines;
    final tip = lines.last;
    expect((tip.args['category']! as CategoryArg).categoryId, 'b');
  });

  testWidgets('Explain entry on the S-20 card opens S-21 with explainer open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(const ChartsScreen(), locale: _en, overrides: _overrides()),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ChartsScreen)));
    await tester.tap(find.text(l.insightsChartsExplain).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChartDetailScreen), findsOneWidget);
    expect(
      find.bySemanticsLabel(l.insightsChartDetailTypingA11y),
      findsOneWidget,
    );
    await _typed(tester);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
