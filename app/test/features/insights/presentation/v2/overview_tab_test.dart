// T-209: widget tests of the v2 Insights Overview tab and its shell, one per
// state. AC map: see docs/04-tasks/tasks/T-209.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_period_bar.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/insights/presentation/v2/categories_tab.dart';
import 'package:zaghlol/features/insights/presentation/v2/insights_v2_screen.dart';
import 'package:zaghlol/features/insights/presentation/v2/overview_tab.dart';
import 'package:zaghlol/features/insights/presentation/v2/trends_tab.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../support/hide_amounts_support.dart';
import 'v2_test_support.dart';

const _en = Locale('en');
const _ar = Locale('ar', 'EG');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  List<Override>? overrides,
  HideAmountsHarness? hidden,
  double scale = 1.0,
  bool dark = false,
  Widget child = const ChartsV2Screen(),
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 3600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      child,
      locale: locale,
      scale: scale,
      dark: dark,
      hideAmounts: hidden,
      overrides: overrides ?? v2Overrides(),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ChartsV2Screen)));

final _bidi = RegExp(
  '[${String.fromCharCode(0x2068)}${String.fromCharCode(0x2069)}]',
);

/// The text of the keyed Text, without the bidi isolates around figures.
String _text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).data!.replaceAll(_bidi, '');

/// Presses the pace chart at day [day] and drags there. The plot runs from
/// the start edge (8) to the end edge minus the 52 axis (LTR), mirrored in
/// RTL.
Future<TestGesture> _scrubTo(
  WidgetTester tester,
  int day, {
  bool rtl = false,
}) async {
  final chart = find.byKey(const Key('pace-chart'));
  await tester.ensureVisible(chart);
  await tester.pumpAndSettle();
  final topLeft = tester.getTopLeft(chart);
  final w = tester.getSize(chart).width;
  final h = tester.getSize(chart).height;
  final f = (day - 1) / 30;
  final dx = rtl ? (w - 8) - f * (w - 60) : 8 + f * (w - 60);
  final g = await tester.startGesture(topLeft + Offset(w / 2, h / 2));
  await g.moveBy(const Offset(30, 0));
  await tester.pump();
  await g.moveTo(topLeft + Offset(dx, h / 2));
  await tester.pump();
  return g;
}

void main() {
  group('shell and tabs (AC 1)', () {
    for (final locale in const [_en, _ar]) {
      testWidgets('opens on Overview with three tabs ${locale.languageCode}', (
        tester,
      ) async {
        await _pump(tester, locale: locale, scale: 1.3);
        final l = _l(tester);
        expect(find.text(l.insightsV2TabOverview), findsOneWidget);
        expect(find.text(l.insightsV2TabCategories), findsOneWidget);
        expect(find.text(l.insightsV2TabTrends), findsOneWidget);
        expect(find.byType(OverviewTab), findsOneWidget);
        expect(find.byType(ChartPeriodBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the period bar stays across tabs; tabs 2 and 3 are stubs with '
        'the All charts button', (tester) async {
      await _pump(tester);
      final l = _l(tester);
      await tester.tap(find.text(l.insightsV2TabCategories));
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesTab), findsOneWidget);
      expect(find.byType(ChartPeriodBar), findsOneWidget);
      expect(find.byKey(const Key('charts-all-v2')), findsOneWidget);
      await tester.tap(find.text(l.insightsV2TabTrends));
      await tester.pumpAndSettle();
      expect(find.byType(TrendsTab), findsOneWidget);
      expect(find.byType(ChartPeriodBar), findsOneWidget);
    });

    testWidgets('Insights opens the v2 screen in its Charts segment', (
      tester,
    ) async {
      await _pump(tester, child: const InsightsScreen());
      expect(find.byType(ChartsV2Screen), findsOneWidget);
      expect(find.byType(OverviewTab), findsOneWidget);
    });

    testWidgets('All charts (12) opens the T-189 charts screen unchanged', (
      tester,
    ) async {
      await _pump(tester);
      final button = find.byKey(const Key('charts-all-v2'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(ChartsScreen), findsOneWidget);
      // its own "All charts" toggle is still there
      expect(find.byKey(const Key('charts-all')), findsOneWidget);
    });

    testWidgets('See all categories opens the Categories tab', (tester) async {
      await _pump(tester);
      final see = find.byKey(const Key('cat-see-all'));
      await tester.ensureVisible(see);
      await tester.tap(see);
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesTab), findsOneWidget);
      expect(find.byType(OverviewTab), findsNothing);
    });
  });

  group('hero pace card', () {
    testWidgets('number, day, comparison, projection and stats (AC 3, 4)', (
      tester,
    ) async {
      await _pump(tester);
      expect(_text(tester, 'hero-spent'), contains('13,650'));
      expect(_text(tester, 'hero-day'), 'Day 20 of 31');
      // 13,650 against 15,900 by the same day last month
      expect(
        _text(tester, 'hero-vs'),
        'EGP 2,250 less than by this day last month',
      );
      expect(find.textContaining('▼ 14%'), findsOneWidget);
      // 13,650 / 20 * 31 = 21,157.50
      expect(_text(tester, 'hero-projection'), contains('21,157.50'));
      // The caption names the period it projects (T-218).
      expect(_text(tester, 'hero-projection'), contains('end this month'));
      expect(_text(tester, 'hero-projection'), contains('under your budget'));
      expect(_text(tester, 'hero-projection'), contains('22,000'));
      expect(find.byKey(const Key('stat-income')), findsOneWidget);
      expect(find.textContaining('32,000'), findsOneWidget);
      // 22,000 - 13,650
      expect(find.textContaining('8,350'), findsOneWidget);
      // the three coming bills (450 + 1,200 + 750) and the later one (100)
      expect(find.byKey(const Key('stat-bills')), findsOneWidget);
      expect(find.textContaining('2,500'), findsOneWidget);
    });

    testWidgets('Arabic copy, Arabic-Indic digits and «شهر»', (tester) async {
      await _pump(tester, locale: _ar);
      expect(_text(tester, 'hero-spent'), contains('١٣٬٦٥٠'));
      expect(_text(tester, 'hero-day'), 'اليوم ٢٠ من ٣١');
      expect(_text(tester, 'hero-vs'), contains('نفس اليوم الشهر اللي فات'));
      expect(_text(tester, 'hero-projection'), contains('الشهر'));
    });

    testWidgets('over budget says so', (tester) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          pace: samplePace(daily: [for (var i = 0; i < 20; i++) 150000]),
        ),
      );
      expect(_text(tester, 'hero-projection'), contains('over your budget'));
    });

    testWidgets('no budget: no left-in-budget stat, no budget wording', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: v2Overrides(pace: samplePace(budget: false)),
      );
      expect(find.byKey(const Key('stat-left')), findsNothing);
      expect(_text(tester, 'hero-projection'), isNot(contains('budget')));
      expect(find.text(_l(tester).insightsV2LegendBudget), findsNothing);
    });

    testWidgets('thin data (2 days): the number and a not-enough-data line', (
      tester,
    ) async {
      await _pump(tester, overrides: v2Overrides(pace: samplePace(elapsed: 2)));
      expect(find.byKey(const Key('hero-spent')), findsOneWidget);
      expect(find.byKey(const Key('hero-thin')), findsOneWidget);
      expect(find.byKey(const Key('hero-vs')), findsNothing);
      expect(find.byKey(const Key('hero-projection')), findsNothing);
    });

    testWidgets('thin data (no previous period)', (tester) async {
      await _pump(
        tester,
        overrides: v2Overrides(pace: samplePace(previous: false)),
      );
      expect(find.byKey(const Key('hero-thin')), findsOneWidget);
      expect(find.text(_l(tester).insightsV2LegendLast), findsNothing);
      // the line and the projection still show
      expect(find.byKey(const Key('hero-projection')), findsOneWidget);
    });

    testWidgets('closed period: whole line, no projection, compares totals', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          pace: samplePace(
            closed: true,
            elapsed: 31,
            daily: [for (var i = 0; i < 31; i++) 50000],
          ),
        ),
      );
      final l = _l(tester);
      expect(find.text(l.insightsV2HeroLabelClosed), findsOneWidget);
      expect(find.byKey(const Key('hero-day')), findsNothing);
      expect(find.byKey(const Key('hero-projection')), findsOneWidget);
      expect(_text(tester, 'hero-projection'), contains('under your budget'));
      expect(find.text(l.insightsV2LegendProjected), findsNothing);
      expect(find.byKey(const Key('stat-bills')), findsNothing);
      expect(_text(tester, 'hero-vs'), contains('less than last month'));
    });

    testWidgets('other currencies sit under the hero, never summed (AC 3)', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          others: [usdM(120), Money(Currency.of('GBP'), 5000)],
        ),
      );
      expect(_text(tester, 'hero-other-USD'), contains('120'));
      expect(_text(tester, 'hero-other-USD'), contains('USD'));
      expect(_text(tester, 'hero-other-GBP'), contains('50'));
      expect(_text(tester, 'hero-spent'), contains('13,650'));
      expect(_text(tester, 'hero-spent'), isNot(contains('170')));
    });

    testWidgets('zero transactions: no crash anywhere', (tester) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          pace: samplePace(daily: const [], previous: false, budget: false),
          donut: const ChartNotEnoughData(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          ),
          saved: const ChartNotEnoughData(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          ),
          dues: const [],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_text(tester, 'hero-spent'), contains('0'));
      expect(find.byKey(const Key('hero-thin')), findsOneWidget);
      expect(find.text(_l(tester).insightsV2UpTitle), findsNothing);
    });

    testWidgets('loading shows a skeleton, an error shows retry', (
      tester,
    ) async {
      await _pump(tester, overrides: v2Overrides(paceError: true));
      expect(find.text(_l(tester).insightsChartsRetry), findsWidgets);
      expect(find.byKey(const Key('hero-spent')), findsNothing);
      expect(
        find.byKey(const Key('cat-see-all')),
        findsOneWidget,
        reason: 'one failing card never blanks the page',
      );
    });
  });

  group('scrub (AC 1 of the hero)', () {
    testWidgets('press and drag shows day, spent to date and last month', (
      tester,
    ) async {
      await _pump(tester);
      final g = await _scrubTo(tester, 14);
      final tip = find.byKey(const Key('pace-tip'));
      expect(tip, findsOneWidget);
      // day 14 of the mockup: 9,800 spent, 11,200 last month
      expect(find.textContaining('Day 14 · spent to date'), findsOneWidget);
      expect(find.textContaining('9,800'), findsOneWidget);
      expect(find.textContaining('Last month: '), findsOneWidget);
      expect(find.textContaining('11,200'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pace-tip')), findsNothing);
    });

    testWidgets('RTL scrubs the mirrored axis', (tester) async {
      await _pump(tester, locale: _ar);
      final g = await _scrubTo(tester, 14, rtl: true);
      expect(find.textContaining('يوم ١٤'), findsOneWidget);
      expect(find.textContaining('٩٬٨٠٠'), findsOneWidget);
      expect(find.textContaining('الشهر اللي فات'), findsWidgets);
      await g.up();
    });

    testWidgets('scrub is clamped to the days so far', (tester) async {
      await _pump(tester);
      final g = await _scrubTo(tester, 31);
      expect(find.textContaining('Day 20 · spent to date'), findsOneWidget);
      await g.up();
    });
  });

  group('hide amounts (AC 5)', () {
    testWidgets('figures and the tooltip show the mask; percentages stay', (
      tester,
    ) async {
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      expect(_text(tester, 'hero-spent'), contains('****'));
      expect(_text(tester, 'hero-spent'), isNot(contains('13')));
      expect(_text(tester, 'hero-vs'), contains('****'));
      expect(_text(tester, 'hero-projection'), contains('****'));
      expect(find.textContaining('▼ 14%'), findsOneWidget);
      expect(find.textContaining('13,650'), findsNothing);
      expect(find.textContaining('32,000'), findsNothing);
      expect(_text(tester, 'cat-amount-food'), contains('****'));
      expect(find.textContaining('▲ 12%'), findsOneWidget);
      final g = await _scrubTo(tester, 14);
      expect(find.textContaining('Day 14 · spent to date'), findsOneWidget);
      expect(find.textContaining('9,800'), findsNothing);
      expect(find.textContaining('11,200'), findsNothing);
      await g.up();
    });

    testWidgets('the spoken labels never say the mask glyphs', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      final l = _l(tester);
      expect(find.bySemanticsLabel(RegExp(r'\*\*\*\*')), findsNothing);
      expect(find.bySemanticsLabel(RegExp(l.commonAmountHidden)), findsWidgets);
      handle.dispose();
    });
  });

  group('where it went', () {
    testWidgets('top four, ranked, with the previous same-days tick', (
      tester,
    ) async {
      await _pump(tester);
      for (final id in ['food', 'bills', 'transport', 'shop']) {
        expect(find.byKey(Key('cat-bar-$id')), findsOneWidget, reason: id);
      }
      expect(find.byKey(const Key('cat-bar-misc')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const Key('cat-bar-food'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('cat-bar-bills'))).dy),
      );
      // food: 4,100 against 3,650; bills: 2,900 against 2,900
      expect(find.textContaining('▲ 12%'), findsOneWidget);
      expect(
        find.textContaining('= same'),
        findsNWidgets(2),
      ); // chip + subtitle
      expect(find.textContaining('▼ 8%'), findsOneWidget);
      expect(find.textContaining('▲ 30%'), findsOneWidget);
      // bar widths are in proportion: bills / food = 2,900 / 4,100
      final food = tester.getSize(find.byKey(const Key('cat-bar-food'))).width;
      final bills = tester
          .getSize(find.byKey(const Key('cat-bar-bills')))
          .width;
      expect(bills / food, closeTo(2900 / 4100, 0.01));
      // the tick of food sits at 3,650 / 4,100 of the track
      final tick = tester.getTopLeft(find.byKey(const Key('cat-tick-food'))).dx;
      final barLeft = tester
          .getTopLeft(find.byKey(const Key('cat-bar-food')))
          .dx;
      expect(tick - barLeft, closeTo(food * 3650 / 4100 - 1, 1.5));
    });

    testWidgets('RTL: the bars grow from the right', (tester) async {
      await _pump(tester, locale: _ar);
      final food = find.byKey(const Key('cat-bar-food'));
      final bills = find.byKey(const Key('cat-bar-bills'));
      // the full bar fills the track; a shorter one hangs from the same end
      expect(
        tester.getTopRight(bills).dx,
        closeTo(tester.getTopRight(food).dx, 0.5),
      );
      expect(
        tester.getTopLeft(bills).dx,
        greaterThan(tester.getTopLeft(food).dx + 20),
      );
    });

    testWidgets('empty: a thin state, not an error', (tester) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          donut: const ChartNotEnoughData(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          ),
        ),
      );
      expect(find.text(_l(tester).insightsThinNoData), findsWidgets);
    });
  });

  group('saved each month', () {
    testWidgets(
      'semantics name every month with its figure, projected marked',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester);
        expect(find.text(_l(tester).insightsV2SavedTitle), findsOneWidget);
        final label = find.bySemanticsLabel(RegExp('Saved each month chart'));
        expect(label, findsOneWidget);
        final text = tester.getSemantics(label).label;
        expect(text, contains('Jun: '));
        expect(text, contains('5,200'));
        expect(text, contains('Aug: '));
        expect(text, contains('1,400'));
        expect(text, contains('Nov (projected): '));
        expect(text, contains('10,800'));
        handle.dispose();
      },
    );

    testWidgets('not enough data is a thin state', (tester) async {
      await _pump(
        tester,
        overrides: v2Overrides(
          saved: const ChartNotEnoughData(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          ),
        ),
      );
      expect(find.text(_l(tester).insightsChartsEmptyCycle), findsWidgets);
    });
  });

  group('coming up', () {
    testWidgets('the next three with "in N days" and the amount', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Coming up'), findsOneWidget);
      expect(find.text('WE internet'), findsOneWidget);
      expect(find.text('valU instalment'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Later'), findsNothing, reason: 'only three');
      expect(find.text('In 3 days'), findsOneWidget);
      expect(find.text('In 6 days'), findsOneWidget);
      expect(find.text('In 9 days'), findsOneWidget);
      expect(find.textContaining('450'), findsWidgets);
    });

    testWidgets('Arabic plural words', (tester) async {
      await _pump(tester, locale: _ar);
      expect(find.text('بعد ٣ أيام'), findsOneWidget);
      expect(find.text('بعد ٦ أيام'), findsOneWidget);
    });

    testWidgets('hidden when nothing is due', (tester) async {
      await _pump(tester, overrides: v2Overrides(dues: const []));
      expect(find.text('Coming up'), findsNothing);
    });
  });

  group('layout (AC 7)', () {
    for (final locale in const [_en, _ar]) {
      for (final dark in [false, true]) {
        testWidgets(
          'text scale 1.3 does not overflow ${locale.languageCode} dark=$dark',
          (tester) async {
            await _pump(tester, locale: locale, dark: dark, scale: 1.3);
            expect(tester.takeException(), isNull);
            final target = find.byKey(const Key('charts-all-v2'));
            await tester.ensureVisible(target);
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          },
        );
      }
    }

    testWidgets('the pace chart carries a spoken summary and a hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final l = _l(tester);
      final label = find.bySemanticsLabel(RegExp('Spending pace chart'));
      expect(label, findsOneWidget);
      final node = tester.getSemantics(label);
      expect(node.label, contains('by day 20 of 31 you spent'));
      expect(node.label, contains('13,650'));
      expect(node.label, contains('Last month by the same day'));
      expect(node.hint, l.insightsV2ScrubHint);
      handle.dispose();
    });
  });
}
