// QA (PO request, 2026-11-26): "Explain this chart" must be easy to read and
// must reflect the actual data. One synthetic month with hand-computed
// figures is pushed through the real engine (explainChart) and the real
// renderer (renderExplanationLine) in English and Arabic; the sentences are
// checked against the figures worked out by hand in the comments.
// Set QA_PRINT_EXPLANATIONS=1 to print every sentence for a reading review.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_l10n.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../support/hide_amounts_support.dart';

final egp = Currency.of('EGP');
Money e(String major) => Money.parse(major, egp);

const _names = {
  'rent': 'Rent',
  'groceries': 'Groceries',
  'dining': 'Eating out',
  'shopping': 'Shopping',
  'transport': 'Transport',
};

final period = ChartPeriod.month(2026, 3);
final prevPeriod = ChartPeriod.month(2026, 2);

CategorySlice slice(String id, String amount, int bp) =>
    CategorySlice(categoryId: id, amount: e(amount), shareBp: bp, count: 4);

// March: income 20,000; spend 23,500 (short by 3,500).
// Rent 8,000 (34%), groceries 5,000 (21%), dining 4,500 (19%),
// shopping 3,500 (15%), transport 2,500 (11%).
final marchSlices = [
  slice('rent', '8000.00', 3404),
  slice('groceries', '5000.00', 2128),
  slice('dining', '4500.00', 1915),
  slice('shopping', '3500.00', 1489),
  slice('transport', '2500.00', 1064),
];
final march = CashFlowPoint(
  period: period,
  income: e('20000.00'),
  spend: e('23500.00'),
  isPartial: false,
);
// February: income 20,000; spend 17,000 (saved 3,000 = 15%).
final february = CashFlowPoint(
  period: prevPeriod,
  income: e('20000.00'),
  spend: e('17000.00'),
  isPartial: false,
);

Future<List<String>> render(
  WidgetTester t,
  String lang,
  ExplainInput input,
  ExplanationTier tier, {
  ExplainContext? context,
}) async {
  var out = <String>[];
  await t.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...amountsShown(),
        digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.western)),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (ctx, ref, _) {
            final f = ExplainFormat.of(
              ctx,
              ref,
              (id) => _names[id] ?? 'Other',
              now: lang == 'ar' ? 'الشهر ده' : 'this month',
              prev: lang == 'ar' ? 'الشهر اللي فات' : 'last month',
            );
            final x = explainChart(input, tier, context: context);
            out = [for (final l in x.lines) renderExplanationLine(f, l)];
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (Platform.environment['QA_PRINT_EXPLANATIONS'] == '1') {
    // ignore: avoid_print
    print('[$lang ${tier.name} ${input.chart.name}]\n  ${out.join('\n  ')}');
  }
  return out;
}

/// Every sentence is complete: no unfilled placeholder, no "null", no raw
/// minor units (a 6+ digit run with no separator), no doubled spaces.
void expectClean(List<String> lines, String where) {
  expect(lines, isNotEmpty, reason: '$where: nothing was explained');
  for (final s in lines) {
    expect(s.trim(), isNotEmpty, reason: where);
    expect(s, isNot(contains('{')), reason: '$where: $s');
    expect(s, isNot(contains('}')), reason: '$where: $s');
    expect(s, isNot(contains('null')), reason: '$where: $s');
    expect(RegExp(r'\d{6,}').hasMatch(s), isFalse, reason: '$where: $s');
    expect(s, isNot(contains('  ')), reason: '$where: "$s"');
    expect(s.length, lessThan(260), reason: '$where: too long to be easy');
  }
}

void expectHas(List<String> lines, List<String> figures, String where) {
  final all = lines.join(' ');
  for (final f in figures) {
    expect(all, contains(f), reason: '$where should mention $f, got: $all');
  }
}

void main() {
  for (final lang in ['en', 'ar']) {
    group('explanations reflect the data ($lang)', () {
      testWidgets('cash flow, short month: 20,000 in, 23,500 out, gap 3,500', (
        t,
      ) async {
        final input = CashFlowExplainInput(
          current: march,
          previous: february,
          categories: marchSlices,
        );
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, 'cash flow basic');
        expectHas(basic, ['20,000', '23,500', '3,500'], 'cash flow basic');
        final deep = await render(t, lang, input, ExplanationTier.deep);
        expectClean(deep, 'cash flow deep');
        expectHas(deep, ['20,000', '23,500', '3,500'], 'cash flow deep');
      });

      testWidgets('cash flow, good month: saved 3,000 = 15% of income', (
        t,
      ) async {
        final input = CashFlowExplainInput(current: february);
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, 'cash flow surplus');
        expectHas(basic, ['3,000', '15%'], 'cash flow surplus');
        // The suggested move is half of what was saved.
        expectHas(basic, ['1,500'], 'cash flow surplus tip');
      });

      testWidgets('categories: rent 8,000 and groceries 5,000 lead', (t) async {
        final input = CategoriesExplainInput(
          current: CategoryDonut(total: e('23500.00'), slices: marchSlices),
        );
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, 'categories');
        expectHas(basic, ['Rent', 'Groceries'], 'categories');
      });

      testWidgets('burn rate: 12,000 of a 20,000 budget by day 10 of 30', (
        t,
      ) async {
        final cycle = Cycle(
          start: CivilDate(2026, 3, 1),
          end: CivilDate(2026, 3, 30),
        );
        final curve = BurnCurve(
          cycle: cycle,
          elapsedDays: 10,
          cumulative: [for (var d = 1; d <= 10; d++) Money(egp, 120000 * d)],
          budget: e('20000.00'),
          projectedTotal: e('36000.00'),
        );
        final basic = await render(
          t,
          lang,
          BurnRateExplainInput(current: curve),
          ExplanationTier.basic,
        );
        expectClean(basic, 'burn rate');
        // 8,000 left over days 10..30 = 21 days = 380.95 a day.
        expectHas(basic, ['12,000', '20,000', '380.95'], 'burn rate');
      });

      testWidgets('50/30/20: needs 50%, wants 40%, savings 10%', (t) async {
        final input = Rule503020ExplainInput(
          current: FiftyThirtyTwenty(
            income: e('20000.00'),
            needs: e('10000.00'),
            wants: e('8000.00'),
            savings: e('2000.00'),
            other: e('0.00'),
          ),
        );
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, '50/30/20');
        expectHas(basic, ['50%', '40%', '10%'], '50/30/20');
        // Wants are 2,000 over their 30% (6,000).
        expectHas(basic, ['2,000'], '50/30/20 tip');
      });

      testWidgets('top merchants: Carrefour 3,200 in 6 visits, Talabat 2,100', (
        t,
      ) async {
        final cur = [
          MerchantSpend(
            merchantNorm: 'talabat',
            name: 'Talabat',
            amount: e('2100.00'),
            count: 9,
          ),
          MerchantSpend(
            merchantNorm: 'carrefour',
            name: 'Carrefour',
            amount: e('3200.00'),
            count: 6,
          ),
        ];
        final basic = await render(
          t,
          lang,
          MerchantsExplainInput(current: cur),
          ExplanationTier.basic,
        );
        expectClean(basic, 'merchants');
        expectHas(basic, ['Carrefour', '3,200', 'Talabat'], 'merchants');
        // BUG-021: the visit count is labelled, not a bare "(6)".
        expectHas(basic, [
          lang == 'ar' ? 'عدد المرات: 6' : 'visits: 6',
        ], 'visits');
      });

      testWidgets('subscriptions: 350 a month = 4,200 a year', (t) async {
        SubscriptionCost sub(String n, String monthly, String annual) =>
            SubscriptionCost(
              itemId: n,
              name: n,
              amount: e(monthly),
              annual: e(annual),
            );
        final input = SubscriptionsExplainInput(
          current: SubscriptionsAnnual(
            items: [
              sub('Netflix', '200.00', '2400.00'),
              sub('Spotify', '100.00', '1200.00'),
              sub('iCloud', '50.00', '600.00'),
            ],
            annualTotal: e('4200.00'),
          ),
        );
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, 'subscriptions');
        expectHas(basic, ['350', '4,200', 'Netflix'], 'subscriptions');
      });

      testWidgets('month vs average: 12,000 against a 10,000 average', (
        t,
      ) async {
        CategoryComparison cc(String id, String cur, String avg, int bp) =>
            CategoryComparison(
              categoryId: id,
              current: e(cur),
              average: e(avg),
              deltaBp: bp,
            );
        final input = VsAverageExplainInput(
          current: MonthVsAverage(
            current: e('12000.00'),
            average: e('10000.00'),
            deltaBp: 2000,
            cyclesCounted: 3,
            elapsedDays: 15,
            byCategory: [
              cc('dining', '4500.00', '3000.00', 5000),
              cc('shopping', '1500.00', '3000.00', -5000),
            ],
          ),
        );
        final basic = await render(t, lang, input, ExplanationTier.basic);
        expectClean(basic, 'vs average');
        expectHas(basic, ['Eating out', '50%'], 'vs average');
      });
    });
  }
}
