// T-210: widget tests of the Categories tab, one per state.
//
// AC map (docs/04-tasks/tasks/T-210.md):
//  1 all categories, uncategorized own label, other currencies: 'lists every
//    category', 'uncategorized', 'other currency'
//  2 sort: 'sort by change', domain tests in category_tab_models_test.dart
//  3 strip: 'share strip' (+ domain tests)
//  4 trend: 'selected category trend'
//  5 gate/hide/RTL/digits: 'hide amounts', 'RTL', 'gate is the donut gate',
//    'thin / error / loading'
//  6 goldens: categories_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/insights/domain/category_tab_models.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/insights/presentation/v2/categories_tab.dart';
import 'package:zaghlol/features/insights/presentation/v2/insights_v2_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../support/hide_amounts_support.dart';
import 'categories_test_support.dart';

const _en = Locale('en');
const _ar = Locale('ar', 'EG');

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  List<Override>? overrides,
  HideAmountsHarness? hidden,
  double scale = 1.0,
  bool dark = false,
  bool settle = true,
  List<Override> inner = const [],
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      ProviderScope(overrides: inner, child: const CategoriesTab()),
      locale: locale,
      scale: scale,
      dark: dark,
      hideAmounts: hidden,
      overrides: overrides ?? catsOverrides(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(CategoriesTab)));

final _bidi = RegExp(
  '[${String.fromCharCode(0x2068)}${String.fromCharCode(0x2069)}]',
);
String _text(WidgetTester t, String key) =>
    t.widget<Text>(find.byKey(Key(key))).data!.replaceAll(_bidi, '');

Finder _has(String s) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').replaceAll(_bidi, '').contains(s),
);

double _top(WidgetTester t, String id) =>
    t.getTopLeft(find.byKey(Key('cat-bar-$id'))).dy;

CategoryDonut _donut(Map<String?, int> m, {int count = 3}) => CategoryDonut(
  total: egpM(m.values.fold(0, (a, b) => a + b)),
  slices: [
    for (final e in m.entries)
      CategorySlice(
        categoryId: e.key,
        amount: egpM(e.value),
        shareBp: 1000,
        count: count,
      ),
  ],
);

void main() {
  group('data state', () {
    for (final locale in const [_en, _ar]) {
      testWidgets('title, total and count; no overflow at 1.3x '
          '${locale.languageCode}', (tester) async {
        await _pump(tester, locale: locale, scale: 1.3);
        final l = _l(tester);
        expect(find.text(l.insightsV2CatsTitle), findsOneWidget);
        expect(find.byKey(const Key('cats-sort')), findsOneWidget);
        expect(find.byKey(const Key('charts-all-v2')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('lists every category (no top-4 cut), largest first', (
      tester,
    ) async {
      await _pump(tester);
      for (final id in ['food', 'bills', 'transport', 'shop', 'misc']) {
        expect(find.byKey(Key('cat-bar-$id')), findsOneWidget, reason: id);
      }
      expect(_top(tester, 'food'), lessThan(_top(tester, 'bills')));
      expect(_top(tester, 'shop'), lessThan(_top(tester, 'misc')));
      expect(_has('EGP 12,850 across 5 categories'), findsOneWidget);
      expect(_text(tester, 'cat-amount-food'), contains('4,100'));
      // previous-period tick and change chip are the T-209 row
      expect(find.byKey(const Key('cat-tick-food')), findsOneWidget);
      expect(find.textContaining('▲ 12%'), findsOneWidget);
    });

    testWidgets('uncategorized has its own label', (tester) async {
      await _pump(
        tester,
        overrides: catsOverrides(
          donut: ChartReady(_donut({'food': 4100, null: 900})),
        ),
      );
      expect(find.byKey(const Key('cat-bar-null')), findsOneWidget);
      expect(
        find.text(_l(tester).transactionsListFilterUncategorized),
        findsWidgets,
      );
    });

    testWidgets('other currency is listed on its own, never summed', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: catsOverrides(others: [Money(Currency.of('USD'), 12000)]),
      );
      expect(find.byKey(const Key('cats-other-USD')), findsOneWidget);
      expect(_has('EGP 12,850'), findsWidgets);
      expect(_has('12,970'), findsNothing);
    });
  });

  group('sort', () {
    testWidgets('sort by change reorders; back to largest first', (
      tester,
    ) async {
      await _pump(tester);
      // moves: shop +450, food +450, misc +150, transport -200, bills 0
      await tester.tap(find.byKey(const Key('cats-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cats-sort-change')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'cats-sort-label'), 'Biggest change');
      // tie (450 each) broken by name: Food & drink before Shopping
      expect(_top(tester, 'food'), lessThan(_top(tester, 'shop')));
      expect(_top(tester, 'shop'), lessThan(_top(tester, 'transport')));
      expect(_top(tester, 'transport'), lessThan(_top(tester, 'bills')));
      await tester.tap(find.byKey(const Key('cats-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cats-sort-amount')));
      await tester.pumpAndSettle();
      expect(_top(tester, 'food'), lessThan(_top(tester, 'bills')));
    });
  });

  group('share strip', () {
    testWidgets('segments with 2 px gaps; at most six named plus Other', (
      tester,
    ) async {
      final m = {for (var i = 0; i < 8; i++) 'c$i': 1000 - i * 50};
      await _pump(
        tester,
        overrides: catsOverrides(donut: ChartReady(_donut(m))),
      );
      expect(find.byKey(const Key('cats-strip-5')), findsOneWidget);
      expect(find.byKey(const Key('cats-strip-6')), findsOneWidget);
      expect(find.byKey(const Key('cats-strip-7')), findsNothing);
      final a = tester.getTopRight(find.byKey(const Key('cats-strip-0'))).dx;
      final b = tester.getTopLeft(find.byKey(const Key('cats-strip-1'))).dx;
      expect(b - a, closeTo(2, 0.01));
    });
  });

  group('selected category', () {
    testWidgets('the first row is selected; its trend has six bars with the '
        'last one open', (tester) async {
      String? asked = 'unset';
      await _pump(
        tester,
        overrides: catsOverrides(onTrend: (id) => asked = id),
      );
      expect(asked, 'food');
      expect(_text(tester, 'cats-tip'), contains('Food & drink · EGP 4,100'));
      expect(_text(tester, 'cats-tip'), contains('3 txns'));
      expect(find.byKey(const Key('cats-trend')), findsOneWidget);
      expect(find.byKey(const Key('cats-trend-open')), findsOneWidget);
      expect(find.text('Food & drink, 6 months'), findsOneWidget);
    });

    testWidgets('tapping a row selects it and reloads the trend', (
      tester,
    ) async {
      String? asked;
      await _pump(
        tester,
        overrides: catsOverrides(onTrend: (id) => asked = id),
      );
      await tester.tap(find.byKey(const Key('cat-bar-bills')));
      await tester.pumpAndSettle();
      expect(asked, 'bills');
      expect(_text(tester, 'cats-tip'), contains('Bills · EGP 2,900'));
    });

    testWidgets('no open note when the last period is closed', (tester) async {
      await _pump(
        tester,
        overrides: catsOverrides(
          trend: [for (final b in sampleTrend()) b]
              .map(
                (b) => CategoryTrendBar(
                  period: b.period,
                  minor: b.minor,
                  inProgress: false,
                ),
              )
              .toList(),
        ),
      );
      expect(find.byKey(const Key('cats-trend-open')), findsNothing);
    });

    testWidgets('Open transactions opens the drill-down', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.byKey(const Key('cats-open-txns')));
      await tester.tap(find.byKey(const Key('cats-open-txns')));
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesTab), findsNothing);
    });

    testWidgets('trend error offers retry', (tester) async {
      await _pump(tester, overrides: catsOverrides(trendError: true));
      expect(find.text(_l(tester).insightsChartsRetry), findsWidgets);
    });
  });

  group('states', () {
    testWidgets('no spending: a thin state', (tester) async {
      await _pump(
        tester,
        overrides: catsOverrides(
          donut: const ChartNotEnoughData(
            NotEnoughReason.noData,
            have: 0,
            need: 1,
          ),
        ),
      );
      expect(find.text(_l(tester).insightsThinNoData), findsOneWidget);
      expect(find.byKey(const Key('cats-trend')), findsNothing);
    });

    testWidgets('loading shows a skeleton', (tester) async {
      await _pump(
        tester,
        settle: false,
        inner: [
          donutChartProvider.overrideWith(
            (ref, code) => Future<ChartResult<CategoryDonut>>.delayed(
              const Duration(days: 1),
            ),
          ),
        ],
      );
      expect(find.byType(CategoriesTab), findsOneWidget);
      expect(find.byKey(const Key('cats-sort')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('error offers retry', (tester) async {
      await _pump(
        tester,
        inner: [
          donutChartProvider.overrideWith(
            (ref, code) async => throw StateError('boom'),
          ),
        ],
      );
      expect(find.text(_l(tester).insightsChartsRetry), findsWidgets);
    });

    testWidgets('the Categories tab of the shell shows this tab', (
      tester,
    ) async {
      await initDateFormatting();
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          const ChartsV2Screen(),
          locale: _en,
          overrides: catsOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesTab), findsOneWidget);
      expect(find.byKey(const Key('cats-strip')), findsOneWidget);
    });
  });

  group('hide amounts and RTL', () {
    testWidgets('every amount is masked; percentages stay', (tester) async {
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      expect(_text(tester, 'cat-amount-food'), contains('****'));
      expect(find.textContaining('12,850'), findsNothing);
      expect(find.textContaining('4,100'), findsNothing);
      expect(find.textContaining('▲ 12%'), findsOneWidget);
      expect(_text(tester, 'cats-tip'), contains('****'));
    });

    testWidgets('Arabic digits and mirrored bars', (tester) async {
      await _pump(tester, locale: _ar);
      expect(_text(tester, 'cat-amount-food'), contains('٤٬١٠٠'));
      expect(_has('٥ تصنيف'), findsOneWidget);
      final food = find.byKey(const Key('cat-bar-food'));
      final bills = find.byKey(const Key('cat-bar-bills'));
      expect(
        tester.getTopRight(bills).dx,
        closeTo(tester.getTopRight(food).dx, 0.5),
      );
      // the strip starts at the right edge: the first segment is rightmost
      expect(
        tester.getTopLeft(find.byKey(const Key('cats-strip-0'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('cats-strip-4'))).dx,
        ),
      );
    });

    testWidgets('semantics: strip, trend and tip are named', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Share of each category')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('over the last six periods')),
        findsOneWidget,
      );
      h.dispose();
    });
  });
}
