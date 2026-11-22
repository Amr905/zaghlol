// T-189: the redesigned charts screen: summary strip, touch (bar, slice,
// place, line scrub), tap-through to a pre-filtered transactions list,
// thin-data states, hidden amounts. Synthetic data only.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_bodies.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/charts/gold_chart_card.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/transactions_list_screen.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../support/hide_amounts_support.dart';
import '../../../transactions/presentation/list/list_harness.dart' as lh;
import 'charts_test_support.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

List<Override> _drillOverrides(lh.FakeRepo repo) => [
  transactionRepositoryProvider.overrideWith((ref) async => repo),
  txnLookupsProvider.overrideWith((ref) async => lh.lookups),
  clockProvider.overrideWithValue(() => lh.now),
  localZoneProvider.overrideWithValue(const lh.FixedZone()),
  transactionsChangedProvider.overrideWithValue(const Stream.empty()),
];

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = _en,
  List<Override>? overrides,
  HideAmountsHarness? hidden,
  double scale = 1.0,
  double height = 3200,
  Widget child = const ChartsScreen(),
}) async {
  await tester.binding.setSurfaceSize(Size(390, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      child,
      locale: locale,
      scale: scale,
      hideAmounts: hidden,
      overrides: overrides ?? chartOverrides(),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ChartsScreen)));

String _textOf(WidgetTester t, Key key) =>
    t.widget<Text>(find.byKey(key)).data!;

/// Taps the centre of group [i] of [n] in the cash flow chart, near its base.
Future<void> _tapBar(
  WidgetTester tester,
  int i,
  int n, {
  bool rtl = false,
}) async {
  final rect = tester.getRect(find.byType(BarChart));
  // The value axis takes 44 on one side; the month labels 28 at the bottom.
  final left = rect.left + (rtl ? 44 : 0);
  final width = rect.width - 44;
  final slot = width / n;
  await tester.tapAt(Offset(left + slot * (i + 0.5), rect.bottom - 28 - 6));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoldGate.chartsOpenToFree = true);

  group('summary strip', () {
    for (final locale in const [_en, _ar]) {
      testWidgets('${locale.languageCode}: four figures, changes, baseline', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        final l = _l(tester);
        final ar = locale.languageCode == 'ar';
        String d(String s) => ar
            ? s
                  .replaceAllMapped(
                    RegExp('[0-9]'),
                    (m) => String.fromCharCode(0x660 + int.parse(m[0]!)),
                  )
                  .replaceAll(',', '٬')
            : s;
        expect(
          _textOf(tester, const Key('summary-spent')),
          contains(d('19,800')),
        );
        expect(
          _textOf(tester, const Key('summary-income')),
          contains(d('32,000')),
        );
        expect(
          _textOf(tester, const Key('summary-saved')),
          contains(d('12,200')),
        );
        expect(_textOf(tester, const Key('summary-rate')), contains(d('38')));
        // Spending down is green ▼, income unchanged is "= same", saved up
        // and the rate up in points. No red anywhere: tones are tokens.
        expect(
          find.textContaining(l.insightsChangeDownPct(d('8%'))),
          findsOneWidget,
        );
        expect(find.textContaining(l.insightsChangeSame), findsOneWidget);
        expect(
          find.textContaining(l.insightsChangeUpPct(d('16%'))),
          findsOneWidget,
        );
        expect(
          find.textContaining(l.insightsChangeUpPts(d('5'))),
          findsOneWidget,
        );
        // The baseline is named: the same 17 days of last month (today is
        // day 17 of the cycle).
        expect(
          find.text(
            l.insightsSummaryBaselineDays(
              d('17'),
              l.insightsChartsPeriodPrevCycleNow,
            ),
          ),
          findsOneWidget,
        );
        // Zaghlol's one-liner for "spending down".
        expect(
          find.textContaining(
            l.insightsOneLinerDown(l.insightsChartsPeriodPrevCycleNow),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('spending up is apricot, never red', (tester) async {
      await _pump(
        tester,
        overrides: chartOverrides(
          summary: ChartSummary.compute(
            PeriodTotals(income: egpM(32000), spend: egpM(25000)),
            PeriodTotals(income: egpM(32000), spend: egpM(20000)),
          ),
        ),
      );
      final l = _l(tester);
      final chip = find.ancestor(
        of: find.textContaining(l.insightsChangeUpPct('25%')),
        matching: find.byType(DecoratedBox),
      );
      final box =
          tester.widget<DecoratedBox>(chip.first).decoration as BoxDecoration;
      final colors = ZColors.of(tester.element(find.byType(ChartsScreen)));
      expect(box.color, colors.warningBg);
      expect(box.color, isNot(colors.dangerBg));
    });

    testWidgets('no activity in the period: Zaghlol line, no tiles', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: chartOverrides(
          summary: ChartSummary.compute(
            PeriodTotals(income: egpM(0), spend: egpM(0)),
            PeriodTotals(income: egpM(0), spend: egpM(0)),
          ),
        ),
      );
      expect(find.text(_l(tester).insightsSummaryEmpty), findsOneWidget);
      expect(find.byKey(const Key('summary-spent')), findsNothing);
    });

    testWidgets('hidden amounts: figures are ****, percentages stay', (
      tester,
    ) async {
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      final l = _l(tester);
      expect(_textOf(tester, const Key('summary-spent')), contains('****'));
      expect(_textOf(tester, const Key('summary-income')), contains('****'));
      expect(_textOf(tester, const Key('summary-saved')), contains('****'));
      expect(_textOf(tester, const Key('summary-rate')), contains('38%'));
      expect(
        find.textContaining(l.insightsChangeDownPct('8%')),
        findsOneWidget,
      );
      expect(find.text(l.insightsChartsHiddenNote), findsOneWidget);
      // No real figure leaks into the cash flow axis or the donut centre.
      expect(find.textContaining('19,800'), findsNothing);
      expect(find.textContaining('32,000'), findsNothing);
      // The shapes are still there.
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('per currency: switching currency re-reads the summary', (
      tester,
    ) async {
      final seen = <String>[];
      await _pump(
        tester,
        overrides: chartOverrides(currencies: [egp, usd], onSummary: seen.add),
      );
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(seen, containsAllInOrder(['EGP', 'USD']));
    });
  });

  group('cash flow', () {
    testWidgets('light value axis: 3-4 gridlines, compact labels', (
      tester,
    ) async {
      await _pump(tester);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final step = chart.data.gridData.horizontalInterval!;
      expect(chart.data.maxY / step, inInclusiveRange(3, 4));
      // Fixture: max 30,000 EGP -> 10K / 20K / 30K labels on the end side.
      expect(find.text('10K'), findsOneWidget);
      expect(find.text('30K'), findsOneWidget);
      expect(chart.data.titlesData.rightTitles.sideTitles.showTitles, isTrue);
      expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isFalse);
    });

    testWidgets('RTL: the axis sits on the other side, Arabic labels', (
      tester,
    ) async {
      await _pump(tester, locale: _ar);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
      expect(chart.data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
      expect(find.text('٣٠ ألف'), findsOneWidget);
    });

    testWidgets('hidden amounts: no axis labels, shapes stay', (tester) async {
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
      expect(find.text('30K'), findsNothing);
    });

    testWidgets('tap a bar: bubble with its figures; tap again clears', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byKey(const Key('cashflow-bubble')), findsNothing);
      await _tapBar(tester, 1, 6);
      expect(find.byKey(const Key('cashflow-bubble')), findsOneWidget);
      expect(find.textContaining('30,000'), findsOneWidget);
      await _tapBar(tester, 1, 6);
      expect(find.byKey(const Key('cashflow-bubble')), findsNothing);
    });

    testWidgets('RTL: the tapped bar maps back to its own month', (
      tester,
    ) async {
      await _pump(tester, locale: _ar);
      // Group 0 on screen is the newest month in RTL (data reversed).
      await _tapBar(tester, 0, 6, rtl: true);
      expect(find.byKey(const Key('cashflow-bubble')), findsOneWidget);
      final bubble = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('cashflow-bubble')),
              matching: find.byType(Text),
            )
            .first,
      );
      // October is the newest fixture bucket (ends 31 Oct).
      expect(bubble.data, contains('أكتوبر'));
    });

    testWidgets('tap-through opens the transactions list for that bar', (
      tester,
    ) async {
      final repo = lh.FakeRepo([
        lh.txnRec('t1', merchant: 'A'),
        lh.txnRec('t2', merchant: 'B', categoryId: 'bills'),
      ]);
      await _pump(
        tester,
        overrides: [...chartOverrides(), ..._drillOverrides(repo)],
      );
      await _tapBar(tester, 5, 6);
      await tester.tap(find.byKey(const Key('cashflow-open')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionsListScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsListScreen)),
      );
      final f = container.read(txnListFilterProvider);
      expect(f.period, TxnPeriod.custom);
      // The last bucket of the fixture: October.
      expect(f.customFrom, CivilDate(2026, 10, 1));
      expect(f.customTo, CivilDate(2026, 10, 31));
      expect(f.type, TxnTypeFilter.expense);
      expect(f.currency?.code, 'EGP');
      expect(find.byType(TxnRow), findsWidgets);
    });
  });

  group('donut', () {
    testWidgets('top 5 + Other with legend rows and change chips', (
      tester,
    ) async {
      final slices = [
        for (var i = 0; i < 7; i++)
          CategorySlice(
            categoryId: 'c$i',
            amount: egpM(700 - i * 100),
            shareBp: 1000 + i,
            count: 2,
          ),
      ];
      await _pump(
        tester,
        overrides: [
          ...chartOverrides(
            donut: ChartReady(CategoryDonut(total: egpM(2800), slices: slices)),
            previousDonut: CategoryDonut(
              total: egpM(500),
              slices: [
                CategorySlice(
                  categoryId: 'c0',
                  amount: egpM(500),
                  shareBp: 10000,
                  count: 1,
                ),
              ],
            ),
          ),
        ],
      );
      final l = _l(tester);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(Key('donut-row-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('donut-row-6')), findsNothing);
      expect(find.text(l.insightsChartsOtherSlice), findsWidgets);
      // c0: 700 vs 500 = up 40%; a category not seen before is "new".
      expect(find.textContaining(l.insightsChangeUpPct('40%')), findsOneWidget);
      expect(find.textContaining(l.insightsChangeNew), findsWidgets);
    });

    testWidgets('tap a slice row: bubble, link, filtered list', (tester) async {
      final repo = lh.FakeRepo([
        lh.txnRec('t1', merchant: 'A'),
        lh.txnRec('t2', merchant: 'B', categoryId: 'bills'),
      ]);
      await _pump(
        tester,
        overrides: [
          ...chartOverrides(
            donut: ChartReady(
              CategoryDonut(
                total: egpM(1000),
                slices: [
                  CategorySlice(
                    categoryId: 'food',
                    amount: egpM(600),
                    shareBp: 6000,
                    count: 23,
                  ),
                  CategorySlice(
                    categoryId: 'bills',
                    amount: egpM(400),
                    shareBp: 4000,
                    count: 3,
                  ),
                ],
              ),
            ),
          ),
          ..._drillOverrides(repo),
        ],
      );
      final l = _l(tester);
      await tester.tap(find.byKey(const Key('donut-row-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('donut-bubble')), findsOneWidget);
      expect(find.text(l.insightsChartsSeeTransactions('23')), findsOneWidget);
      await tester.tap(find.byKey(const Key('donut-open')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsListScreen)),
      );
      final f = container.read(txnListFilterProvider);
      expect(f.categoryIds, {'food'});
      expect(f.period, TxnPeriod.custom);
      // The list shows only that category and the header totals it.
      expect(find.byType(TxnRow), findsOneWidget);
      expect(find.byKey(const Key('drill-total')), findsOneWidget);
    });

    testWidgets('tapping a slice on the ring selects it', (tester) async {
      await _pump(tester);
      final rect = tester.getRect(find.byType(PieChart));
      // The lead slice starts at 12 o'clock and runs clockwise: a point on
      // the ring just right of the top is inside it.
      final radius = rect.width * 0.33 + rect.width * 0.075;
      await tester.tapAt(rect.center + Offset(radius * 0.4, -radius));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('donut-bubble')), findsOneWidget);
    });

    testWidgets('hidden amounts: legend amounts masked, shares stay', (
      tester,
    ) async {
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      expect(find.textContaining('60%'), findsWidgets);
      expect(find.textContaining('600'), findsNothing);
    });
  });

  group('top places', () {
    testWidgets('rows show the count and open that merchant', (tester) async {
      final repo = lh.FakeRepo([
        lh.txnRec('t1', merchant: 'm0'),
        lh.txnRec('t2', merchant: 'm1'),
      ]);
      await _pump(
        tester,
        overrides: [...chartOverrides(), ..._drillOverrides(repo)],
      );
      final l = _l(tester);
      expect(find.text(l.insightsChartsPlaceCount(2, '2')), findsWidgets);
      await tester.tap(find.byKey(const Key('merchant-m0')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsListScreen)),
      );
      final f = container.read(txnListFilterProvider);
      expect(f.merchantNorm, 'm0');
      expect(find.byType(TxnRow), findsOneWidget);
      // The merchant chip names the place and can be removed: the list then
      // shows both merchants.
      expect(find.text('Shop 0'), findsOneWidget);
      container
          .read(txnListFilterProvider.notifier)
          .set(f.copyWith(clearMerchant: true));
      await tester.pumpAndSettle();
      expect(find.byType(TxnRow), findsNWidgets(2));
      expect(find.text('Shop 0'), findsNothing);
    });

    testWidgets('48dp rows', (tester) async {
      await _pump(tester);
      final size = tester.getSize(find.byKey(const Key('merchant-m0')));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('all charts', () {
    testWidgets('the rest stay behind "All charts (12)" and build lazily', (
      tester,
    ) async {
      var burnReads = 0;
      await _pump(
        tester,
        height: 9000,
        overrides: [
          ...chartOverrides(),
          ...goldChartOverrides(onBurn: () => burnReads++),
        ],
      );
      final l = _l(tester);
      expect(find.text(l.insightsChartsAllCharts('12')), findsOneWidget);
      // Not built, not queried (NFR-PERF-04).
      expect(find.byType(GoldChartCard), findsOneWidget); // vs average only
      expect(burnReads, 0);
      await openAllCharts(tester);
      expect(find.byType(GoldChartCard, skipOffstage: false), findsNWidgets(9));
      expect(burnReads, 1);
      expect(find.text(l.insightsChartsFewerCharts), findsOneWidget);
    });
  });

  group('line scrub', () {
    testWidgets('press and drag along the burn line reads each point', (
      tester,
    ) async {
      await _pump(
        tester,
        child: const GoldChartCard(chart: ChartId.burnCurve, code: 'EGP'),
        overrides: [...chartOverrides(), ...goldChartOverrides()],
      );
      expect(find.byKey(const Key('line-bubble')), findsNothing);
      final rect = tester.getRect(find.byType(LineChart));
      final g = await tester.startGesture(
        Offset(rect.left + rect.width * 0.05, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(Offset(rect.left + rect.width * 0.12, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('line-bubble')), findsOneWidget);
      final first = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('line-bubble')),
              matching: find.byType(Text),
            ),
          )
          .data;
      await g.moveTo(Offset(rect.left + rect.width * 0.2, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      final second = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('line-bubble')),
              matching: find.byType(Text),
            ),
          )
          .data;
      await g.up();
      expect(second, isNot(first));
    });
  });

  group('thin data', () {
    testWidgets('below the minimum, Zaghlol says how much is missing', (
      tester,
    ) async {
      await _pump(
        tester,
        child: const GoldChartCard(chart: ChartId.netWorth, code: 'EGP'),
        overrides: [
          ...chartOverrides(),
          ...goldChartOverrides(
            netWorth: const ChartNotEnoughData<List<NetWorthPoint>>(
              NotEnoughReason.tooFewSnapshots,
              have: 0,
              need: 2,
            ),
          ),
        ],
      );
      final l = AppLocalizations.of(tester.element(find.byType(GoldChartCard)));
      expect(
        find.text(
          l.insightsThinNeedMonths(l.insightsChartsMonthsCount(2, '2')),
        ),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('Arabic: the line names the missing months', (tester) async {
      await _pump(
        tester,
        locale: _ar,
        child: const GoldChartCard(chart: ChartId.netWorth, code: 'EGP'),
        overrides: [
          ...chartOverrides(),
          ...goldChartOverrides(
            netWorth: const ChartNotEnoughData<List<NetWorthPoint>>(
              NotEnoughReason.tooFewSnapshots,
              have: 0,
              need: 2,
            ),
          ),
        ],
      );
      expect(find.textContaining('شهرين'), findsOneWidget);
    });

    testWidgets('donut below its minimum shows the missing transactions', (
      tester,
    ) async {
      await _pump(
        tester,
        overrides: chartOverrides(
          donut: const ChartNotEnoughData(
            NotEnoughReason.tooFewTransactions,
            have: 1,
            need: 3,
          ),
        ),
      );
      expect(
        find.text(_l(tester).insightsThinNeedTxns(2, '2')),
        findsOneWidget,
      );
      expect(find.byType(PieChart), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('every chart has a text summary; chips are spoken', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'^Cash flow: income')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Where your money went: ')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Top merchants: ')),
        findsOneWidget,
      );
      // A tile speaks its label, value, change and baseline.
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Spent: .*down 8%.*the same days of last month'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('hidden amounts are never spoken as ****', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hidden: HideAmountsHarness(hidden: true));
      expect(find.bySemanticsLabel(RegExp(r'\*\*\*\*')), findsNothing);
      handle.dispose();
    });

    for (final locale in const [_en, _ar]) {
      testWidgets('${locale.languageCode}: text scale 1.3 does not overflow', (
        tester,
      ) async {
        await _pump(tester, locale: locale, scale: 1.3);
        await tester.tap(find.byKey(const Key('donut-row-0')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('CashFlowBody keeps its static summary API', () {
    expect(CashFlowBody.savedPercent(3800, 10000), 38);
  });
}
