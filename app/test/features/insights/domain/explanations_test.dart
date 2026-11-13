// T-106: the explanation engine. Synthetic numbers only.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final kwd = Currency.of('KWD');

Money e(int minor) => Money(egp, minor);

final period = ChartPeriod.month(2026, 3);
final prevPeriod = ChartPeriod.month(2026, 2);

CashFlowPoint cf(int income, int spend) => CashFlowPoint(
  period: period,
  income: e(income),
  spend: e(spend),
  isPartial: false,
);

CategorySlice slice(String? id, int amount, int bp) =>
    CategorySlice(categoryId: id, amount: e(amount), shareBp: bp, count: 3);

ExplanationLine line(Explanation x, ExplanationKey k) =>
    x.lines.firstWhere((l) => l.key == k);

Explanation basic(ExplainInput i, {ExplainContext? c}) =>
    explainChart(i, ExplanationTier.basic, context: c);
Explanation deep(ExplainInput i, {ExplainContext? c}) =>
    explainChart(i, ExplanationTier.deep, context: c);

void main() {
  group('cash flow', () {
    final cats = [
      slice('rent', 500000, 5000),
      slice('dining', 200000, 2000),
      slice('fun', 100000, 1000),
    ];

    test('short month: gap, trim tip on the largest non-essential', () {
      final x = basic(
        CashFlowExplainInput(current: cf(800000, 900000), categories: cats),
      );
      final f = line(x, ExplanationKey.cashFlowBasic);
      expect(f.select('state'), 'short');
      expect(f.money('income'), e(800000));
      expect(f.money('spent'), e(900000));
      expect(f.money('gap'), e(100000));
      final t = line(x, ExplanationKey.cashFlowTip);
      expect((t.args['category']! as CategoryArg).categoryId, 'dining');
      expect(t.money('target'), e(100000));
    });

    test('tip dropped when no non-essential category can close the gap', () {
      final x = basic(
        CashFlowExplainInput(current: cf(800000, 1200000), categories: cats),
      );
      expect(x.lines.map((l) => l.key), [ExplanationKey.cashFlowBasic]);
    });

    test('essential-only spending is never trimmed (Q-25)', () {
      final x = basic(
        CashFlowExplainInput(
          current: cf(100, 200),
          categories: [slice('rent', 200, 10000), slice('groceries', 50, 10)],
        ),
      );
      expect(x.firstOf(ExplanationPart.tip), isNull);
    });

    test('surplus: saved, percent of income, half as the move target', () {
      final x = basic(CashFlowExplainInput(current: cf(1000000, 700000)));
      final f = line(x, ExplanationKey.cashFlowBasic);
      expect(f.select('state'), 'other');
      expect(f.money('saved'), e(300000));
      expect((f.args['percent']! as PercentArg).bp, 3000);
      expect(line(x, ExplanationKey.cashFlowTip).money('target'), e(150000));
    });

    test('nothing at all, or surplus with no income, explains nothing', () {
      expect(basic(CashFlowExplainInput(current: cf(0, 0))).isEmpty, isTrue);
    });

    test('three-decimal currency keeps its exponent', () {
      final p = CashFlowPoint(
        period: period,
        income: Money(kwd, 1500),
        spend: Money(kwd, 500),
        isPartial: false,
      );
      final x = basic(CashFlowExplainInput(current: p));
      expect(
        line(x, ExplanationKey.cashFlowBasic).money('saved'),
        Money(kwd, 1000),
      );
      expect(
        line(x, ExplanationKey.cashFlowTip).money('target'),
        Money(kwd, 500),
      );
    });

    test('deep: trend vs previous, yearly goal, no basic tip', () {
      final x = deep(
        CashFlowExplainInput(
          current: cf(1000000, 700000),
          previous: cf(1000000, 800000),
        ),
      );
      expect(x.lines.map((l) => l.key), [
        ExplanationKey.cashFlowBasic,
        ExplanationKey.cashFlowDeep,
        ExplanationKey.cashFlowDeepTip,
      ]);
      final d = line(x, ExplanationKey.cashFlowDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(100000));
      expect(
        line(x, ExplanationKey.cashFlowDeepTip).money('yearly'),
        e(3600000),
      );
    });

    test('deep: same net reads as about the same', () {
      final x = deep(
        CashFlowExplainInput(current: cf(1000, 600), previous: cf(900, 500)),
      );
      expect(line(x, ExplanationKey.cashFlowDeep).select('trend'), 'other');
    });
  });

  group('categories', () {
    final donut = CategoryDonut(
      total: e(1000000),
      slices: [
        slice('dining', 200000, 2000),
        slice('groceries', 500000, 5000),
        slice(null, 100000, 1000),
        slice('fun', 200000, 2000),
      ],
    );

    test('top two named slices, uncategorized never named', () {
      final x = basic(CategoriesExplainInput(current: donut));
      final f = line(x, ExplanationKey.categoriesBasic);
      expect((f.args['category']! as CategoryArg).categoryId, 'groceries');
      expect(f.money('amount'), e(500000));
      expect((f.args['percent']! as PercentArg).bp, 5000);
      expect((f.args['category2']! as CategoryArg).categoryId, 'dining');
    });

    test('the cap tip skips groceries (Q-25) and sizes a tenth', () {
      final x = basic(CategoriesExplainInput(current: donut));
      final t = line(x, ExplanationKey.categoriesTip);
      expect((t.args['category']! as CategoryArg).categoryId, 'dining');
      expect(t.money('target'), e(20000));
    });

    test('fewer than two named slices: no explanation', () {
      final one = CategoryDonut(
        total: e(10),
        slices: [slice('fun', 10, 10000)],
      );
      expect(basic(CategoriesExplainInput(current: one)).isEmpty, isTrue);
    });

    test('deep needs the same category in the previous period', () {
      final prev = CategoryDonut(
        total: e(1),
        slices: [slice('groceries', 400000, 4000)],
      );
      final x = deep(CategoriesExplainInput(current: donut, previous: prev));
      final d = line(x, ExplanationKey.categoriesDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(100000));
      final y = deep(
        CategoriesExplainInput(
          current: donut,
          previous: CategoryDonut(total: e(1), slices: [slice('x', 1, 1)]),
        ),
      );
      expect(y.firstOf(ExplanationPart.deepFact), isNull);
      expect(y.firstOf(ExplanationPart.deepTip), isNotNull);
    });
  });

  group('burn rate', () {
    final cycle = Cycle(
      start: CivilDate(2026, 3, 1),
      end: CivilDate(2026, 3, 30),
    );
    BurnCurve curve(
      int daily, {
      int days = 10,
      int? budget = 300000,
      int? proj,
    }) => BurnCurve(
      cycle: cycle,
      elapsedDays: days,
      cumulative: [for (var d = 1; d <= days; d++) e(daily * d)],
      budget: budget == null ? null : e(budget),
      projectedTotal: proj == null ? null : e(proj),
    );

    test('over the ideal line: spent, budget, per day left', () {
      final x = basic(BurnRateExplainInput(current: curve(15000)));
      final f = line(x, ExplanationKey.burnRateBasic);
      expect(f.select('state'), 'over');
      expect(f.money('spent'), e(150000));
      expect(f.money('budget'), e(300000));
      // 150000 left over days 10..30 inclusive = 21 days.
      expect(f.money('perDay'), e(7142));
      expect((f.args['cycleDay']! as CountArg).count, 10);
      expect(line(x, ExplanationKey.burnRateTip).select('state'), 'over');
    });

    test('under the line', () {
      final x = basic(BurnRateExplainInput(current: curve(5000)));
      expect(line(x, ExplanationKey.burnRateBasic).select('state'), 'other');
    });

    test('budget used up: fact stays, tip is dropped', () {
      final x = basic(BurnRateExplainInput(current: curve(40000)));
      expect(line(x, ExplanationKey.burnRateBasic).money('perDay'), e(0));
      expect(x.firstOf(ExplanationPart.tip), isNull);
    });

    test('no budget: nothing to say', () {
      expect(
        basic(BurnRateExplainInput(current: curve(1000, budget: null))).isEmpty,
        isTrue,
      );
    });

    test('deep: same-day comparison, cut target, projection extra', () {
      final x = deep(
        BurnRateExplainInput(
          current: curve(15000, proj: 450000),
          previous: curve(10000, days: 30),
        ),
      );
      final d = line(x, ExplanationKey.burnRateDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(50000));
      // 150000 over / 21 days, rounded up.
      expect(line(x, ExplanationKey.burnRateDeepTip).money('target'), e(7143));
      final p = line(x, ExplanationKey.deepProjection);
      expect(p.select('state'), 'over');
      expect(p.money('projected'), e(450000));
    });

    test('deep tip dropped when the projection fits the budget', () {
      final x = deep(BurnRateExplainInput(current: curve(5000, proj: 250000)));
      expect(x.firstOf(ExplanationPart.deepTip), isNull);
      expect(line(x, ExplanationKey.deepProjection).select('state'), 'other');
    });
  });

  group('50/30/20', () {
    FiftyThirtyTwenty r(int needs, int wants, int savings) => FiftyThirtyTwenty(
      income: e(1000000),
      needs: e(needs),
      wants: e(wants),
      savings: e(savings),
      other: e(0),
    );

    test('wants high: shares and the excess as the tip target', () {
      final x = basic(
        Rule503020ExplainInput(current: r(500000, 400000, 100000)),
      );
      final f = line(x, ExplanationKey.rule503020Basic);
      expect(f.select('state'), 'wantsHigh');
      expect((f.args['wantsPct']! as PercentArg).bp, 4000);
      expect(line(x, ExplanationKey.rule503020Tip).money('target'), e(100000));
    });

    test('savings low', () {
      final x = basic(
        Rule503020ExplainInput(current: r(600000, 300000, 100000)),
      );
      expect(
        line(x, ExplanationKey.rule503020Basic).select('state'),
        'savingsLow',
      );
      expect(line(x, ExplanationKey.rule503020Tip).money('target'), e(100000));
    });

    test('on track', () {
      final x = basic(
        Rule503020ExplainInput(current: r(500000, 300000, 200000)),
      );
      expect(line(x, ExplanationKey.rule503020Basic).select('state'), 'other');
      expect(line(x, ExplanationKey.rule503020Tip).money('target'), e(50000));
    });

    test('no income: nothing', () {
      final z = FiftyThirtyTwenty(
        income: e(0),
        needs: e(0),
        wants: e(0),
        savings: e(0),
        other: e(0),
      );
      expect(basic(Rule503020ExplainInput(current: z)).isEmpty, isTrue);
    });

    test('deep: savings trend and the next 5-point step per year', () {
      final x = deep(
        Rule503020ExplainInput(
          current: r(500000, 300000, 200000),
          previous: r(500000, 300000, 150000),
        ),
      );
      expect(line(x, ExplanationKey.rule503020Deep).select('trend'), 'up');
      final t = line(x, ExplanationKey.rule503020DeepTip);
      expect((t.args['percent']! as PercentArg).bp, 2500);
      expect(t.money('yearly'), e(250000 * 12));
    });
  });

  group('week pattern', () {
    DayHourPattern pat(Map<int, int> byDay, {int peakHour = 21}) =>
        DayHourPattern(
          byWeekday: {
            for (var d = 1; d <= 7; d++)
              d: DayHourCell(spend: e(byDay[d] ?? 0), count: 1),
          },
          byHour: {
            for (var h = 0; h < 24; h++)
              h: DayHourCell(spend: e(h == peakHour ? 1000 : 0), count: 1),
          },
        );

    // March 2026: Fridays 6, 13, 20, 27 (4); Saturdays 7, 14, 21, 28 (4).
    test('top two days, their share, busiest hour, per-day limit', () {
      final x = basic(
        WeekPatternExplainInput(
          current: pat({5: 40000, 6: 20000, 1: 40000}),
          period: period,
        ),
      );
      final f = line(x, ExplanationKey.weekPatternBasic);
      // Tie on 40000 between Monday and Friday: the lower weekday first.
      expect((f.args['peakDay']! as WeekdayArg).isoWeekday, 1);
      expect((f.args['peakDay2']! as WeekdayArg).isoWeekday, 5);
      expect((f.args['percent']! as PercentArg).bp, 8000);
      expect((f.args['time']! as HourArg).hour, 21);
      // Mondays in March 2026: 2, 9, 16, 23, 30 = 5; avg 8000; limit 7200.
      expect(line(x, ExplanationKey.weekPatternTip).money('target'), e(7200));
    });

    test('a single active day says nothing', () {
      expect(
        basic(WeekPatternExplainInput(current: pat({3: 100}), period: period))
            .isEmpty,
        isTrue,
      );
    });

    test('deep: average on the peak day vs the previous period', () {
      final x = deep(
        WeekPatternExplainInput(
          current: pat({5: 40000, 6: 20000}),
          period: period,
          previous: pat({5: 20000}),
          previousPeriod: prevPeriod,
        ),
      );
      final d = line(x, ExplanationKey.weekPatternDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('amount'), e(10000));
      final t = line(x, ExplanationKey.weekPatternDeepTip);
      expect(t.money('target'), e(1000));
      expect(t.money('yearly'), e(52000));
    });
  });

  group('merchants', () {
    MerchantSpend m(String n, int amount, int count) => MerchantSpend(
      merchantNorm: n,
      name: n.toUpperCase(),
      amount: e(amount),
      count: count,
    );

    test('top two by amount, visits as a count', () {
      final x = basic(
        MerchantsExplainInput(current: [m('b', 100, 2), m('a', 900, 7)]),
      );
      final f = line(x, ExplanationKey.merchantsBasic);
      expect((f.args['merchant']! as NameArg).name, 'A');
      expect(f.money('amount'), e(900));
      expect((f.args['visits']! as CountArg).count, 7);
      expect((f.args['merchant2']! as NameArg).name, 'B');
    });

    test('protected merchants are skipped by the tip', () {
      final x = basic(
        MerchantsExplainInput(current: [m('landlord', 900, 1), m('b', 100, 2)]),
        c: ExplainContext(protectedMerchantNorms: {'landlord'}),
      );
      expect(
        (line(x, ExplanationKey.merchantsTip).args['merchant']! as NameArg)
            .name,
        'B',
      );
    });

    test('deep: top-three share, trend, quarter cut, drivers', () {
      final cur = [
        m('a', 500, 5),
        m('b', 300, 3),
        m('c', 100, 1),
        m('d', 50, 1),
      ];
      final prev = [m('a', 400, 4), m('b', 400, 4), m('c', 100, 1)];
      final x = deep(
        MerchantsExplainInput(current: cur, previous: prev),
        c: ExplainContext(
          totalSpend: e(1000),
          merchants: cur,
          previousMerchants: prev,
        ),
      );
      final d = line(x, ExplanationKey.merchantsDeep);
      expect((d.args['percent']! as PercentArg).bp, 9000);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(100));
      final t = line(x, ExplanationKey.merchantsDeepTip);
      expect(t.money('target'), e(125));
      expect(t.money('yearly'), e(1500));
      // Merchants chart gets no projection; drivers only on charts 1,2,3,5,7.
      expect(x.firstOf(ExplanationPart.drivers), isNull);
    });
  });

  group('vs average', () {
    CategoryComparison cc(String? id, int cur, int avg) => CategoryComparison(
      categoryId: id,
      current: e(cur),
      average: e(avg),
      deltaBp: avg == 0 ? null : (cur - avg) * 10000 ~/ avg,
    );
    MonthVsAverage mv(List<CategoryComparison> cats, {int cycles = 3}) =>
        MonthVsAverage(
          current: e(1200),
          average: e(1000),
          deltaBp: 2000,
          cyclesCounted: cycles,
          elapsedDays: 15,
          byCategory: cats,
        );

    test('both: biggest rise and biggest drop', () {
      final x = basic(
        VsAverageExplainInput(
          current: mv([
            cc('dining', 300, 200),
            cc('fun', 50, 100),
            cc('x', 100, 100),
          ]),
        ),
      );
      final f = line(x, ExplanationKey.vsAverageBasic);
      expect(f.select('state'), 'both');
      expect((f.args['percent']! as PercentArg).bp, 5000);
      expect((f.args['percent2']! as PercentArg).bp, 5000);
      expect(line(x, ExplanationKey.vsAverageTip).money('target'), e(100));
    });

    test(
      'rise in an essential category: fact says it, tip does not push it',
      () {
        final x = basic(
          VsAverageExplainInput(current: mv([cc('groceries', 300, 200)])),
        );
        expect(line(x, ExplanationKey.vsAverageBasic).select('state'), 'rise');
        expect(x.firstOf(ExplanationPart.tip), isNull);
      },
    );

    test('close to average', () {
      final x = basic(
        VsAverageExplainInput(current: mv([cc('fun', 101, 100)])),
      );
      expect(line(x, ExplanationKey.vsAverageBasic).select('state'), 'other');
      expect(line(x, ExplanationKey.vsAverageTip).select('state'), 'other');
    });

    test('needs the earlier cycles', () {
      expect(
        basic(VsAverageExplainInput(current: mv([], cycles: 1))).isEmpty,
        isTrue,
      );
    });

    test('deep: overall delta and the limit at the average', () {
      final x = deep(
        VsAverageExplainInput(current: mv([cc('dining', 300, 200)])),
      );
      final d = line(x, ExplanationKey.vsAverageDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(200));
      expect(line(x, ExplanationKey.vsAverageDeepTip).money('target'), e(200));
    });
  });

  group('installments, subscriptions, cards', () {
    test('installments: this month, next to finish, deep totals', () {
      final months = [
        InstallmentMonth(year: 2026, month: 3, total: e(300), dues: const []),
        InstallmentMonth(year: 2026, month: 4, total: e(200), dues: const []),
        InstallmentMonth(year: 2026, month: 5, total: e(100), dues: const []),
      ];
      final input = InstallmentsExplainInput(
        months: months,
        today: CivilDate(2026, 3, 10),
        ends: [
          InstallmentEnd(
            itemId: 'late',
            name: 'Phone',
            endsOn: CivilDate(2026, 9, 1),
            monthly: e(100),
          ),
          InstallmentEnd(
            itemId: 'soon',
            name: 'Fridge',
            endsOn: CivilDate(2026, 5, 1),
            monthly: e(200),
          ),
          InstallmentEnd(
            itemId: 'gone',
            name: 'Old',
            endsOn: CivilDate(2026, 1, 1),
            monthly: e(9),
          ),
        ],
      );
      final f = line(basic(input), ExplanationKey.installmentsBasic);
      expect(f.money('sum'), e(300));
      expect((f.args['item']! as NameArg).name, 'Fridge');
      expect((f.args['month']! as MonthArg).month, 5);
      final x = deep(input);
      final d = line(x, ExplanationKey.installmentsDeep);
      expect(d.money('amount'), e(600));
      expect(d.money('average'), e(200));
      expect(
        line(x, ExplanationKey.installmentsDeepTip).money('monthly'),
        e(200),
      );
    });

    test('installments: nothing owed, nothing said', () {
      expect(
        basic(
          InstallmentsExplainInput(
            months: [
              InstallmentMonth(
                year: 2026,
                month: 3,
                total: e(0),
                dues: const [],
              ),
            ],
            ends: const [],
            today: CivilDate(2026, 3, 1),
          ),
        ).isEmpty,
        isTrue,
      );
    });

    SubscriptionCost sub(String n, int annual) => SubscriptionCost(
      itemId: n,
      name: n,
      amount: e(annual ~/ 12),
      annual: e(annual),
    );

    test('subscriptions: monthly, yearly, priciest', () {
      final s = SubscriptionsAnnual(
        items: [sub('a', 12000), sub('b', 24000), sub('c', 6000)],
        annualTotal: e(42000),
      );
      final x = basic(SubscriptionsExplainInput(current: s));
      final f = line(x, ExplanationKey.subscriptionsBasic);
      expect(f.money('monthly'), e(3500));
      expect(f.money('yearly'), e(42000));
      final t = line(x, ExplanationKey.subscriptionsTip);
      expect((t.args['item']! as NameArg).name, 'b');
      expect(t.money('target'), e(24000));
      final y = deep(
        SubscriptionsExplainInput(
          current: s,
          threeMonthsAgo: SubscriptionsAnnual(
            items: const [],
            annualTotal: e(36000),
          ),
        ),
      );
      final d = line(y, ExplanationKey.subscriptionsDeep);
      expect(d.select('trend'), 'up');
      expect(d.money('delta'), e(500));
      expect(
        line(y, ExplanationKey.subscriptionsDeepTip).money('target'),
        e(36000),
      );
    });

    test('subscriptions: none, nothing', () {
      expect(
        basic(
          SubscriptionsExplainInput(
            current: SubscriptionsAnnual(items: const [], annualTotal: e(0)),
          ),
        ).isEmpty,
        isTrue,
      );
    });

    CardSpend card(String id, String kind, int spend, int bp) => CardSpend(
      accountId: id,
      label: id,
      kind: kind,
      spend: e(spend),
      shareBp: bp,
      count: 2,
    );

    test('cards: credit state carries utilisation', () {
      final cur = [
        card('b', 'debit', 200, 2000),
        card('a', 'credit', 800, 8000),
      ];
      final x = basic(
        CardsExplainInput(current: cur, utilisationBpByAccount: {'a': 4500}),
      );
      final f = line(x, ExplanationKey.cardsBasic);
      expect(f.select('state'), 'credit');
      expect((f.args['utilisation']! as PercentArg).bp, 4500);
      expect((f.args['percent']! as PercentArg).bp, 8000);
      final y = basic(CardsExplainInput(current: cur));
      expect(line(y, ExplanationKey.cardsBasic).select('state'), 'other');
      expect(
        line(y, ExplanationKey.cardsBasic).args.containsKey('utilisation'),
        isFalse,
      );
    });

    test('cards: deep share trend and a limit a tenth below', () {
      final cur = [
        card('a', 'debit', 800, 8000),
        card('b', 'debit', 200, 2000),
      ];
      final x = deep(
        CardsExplainInput(
          current: cur,
          previous: [card('a', 'debit', 500, 5000)],
        ),
      );
      expect(line(x, ExplanationKey.cardsDeep).select('trend'), 'up');
      final t = line(x, ExplanationKey.cardsDeepTip);
      expect(t.money('amount'), e(800));
      expect(t.money('target'), e(720));
    });
  });

  group('net worth', () {
    NetWorthPoint p(int y, int mo, int net) => NetWorthPoint(
      takenOn: CivilDate(y, mo, 1),
      unit: 'EGP',
      assetsMinor: net + 100,
      liabilitiesMinor: 100,
    );

    test('one unit, start and end, never a cross-unit sum', () {
      final x = basic(
        NetWorthExplainInput(
          points: [p(2026, 1, 1000), p(2026, 3, 1300)],
          assetsByTypeLatest: {'gold': 900, 'car': 500},
        ),
      );
      final f = line(x, ExplanationKey.netWorthBasic);
      expect(f.select('trend'), 'up');
      expect((f.args['endAmount']! as UnitAmountArg).minor, 1300);
      expect((f.args['startAmount']! as UnitAmountArg).minor, 1000);
      expect((f.args['month']! as MonthArg).month, 1);
      final t = line(x, ExplanationKey.netWorthTip);
      expect((t.args['assetType']! as AssetTypeArg).type, 'gold');
      expect((t.args['percent']! as PercentArg).bp, 6429);
      expect(
        basic(
          NetWorthExplainInput(
            points: [
              p(2026, 1, 1),
              const NetWorthPoint(
                takenOn: CivilDate.fromEpochDay(20000),
                unit: 'XAU',
                assetsMinor: 1,
                liabilitiesMinor: 0,
              ),
            ],
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('steady: only the end amount', () {
      final x = basic(
        NetWorthExplainInput(points: [p(2026, 1, 1000), p(2026, 3, 1005)]),
      );
      final f = line(x, ExplanationKey.netWorthBasic);
      expect(f.select('trend'), 'other');
      expect(f.args.containsKey('startAmount'), isFalse);
    });

    test('one snapshot is not a trend', () {
      expect(
        basic(NetWorthExplainInput(points: [p(2026, 1, 1)])).isEmpty,
        isTrue,
      );
    });

    test('deep: percent, the asset behind it, estimate in a year', () {
      final x = deep(
        NetWorthExplainInput(
          points: [p(2026, 1, 1000), p(2026, 3, 1300)],
          assetsByTypeFirst: {'gold': 700, 'car': 500},
          assetsByTypeLatest: {'gold': 900, 'car': 500},
        ),
      );
      final d = line(x, ExplanationKey.netWorthDeep);
      expect((d.args['percent']! as PercentArg).bp, 3000);
      expect((d.args['assetType2']! as AssetTypeArg).type, 'gold');
      final t = line(x, ExplanationKey.netWorthDeepTip);
      expect((t.args['projected']! as UnitAmountArg).minor, 1300 + 150 * 12);
    });

    test('deep: a falling net worth has no projection tip', () {
      final x = deep(
        NetWorthExplainInput(
          points: [p(2026, 1, 1000), p(2026, 3, 800)],
          assetsByTypeFirst: {'gold': 900},
          assetsByTypeLatest: {'gold': 700},
        ),
      );
      expect(line(x, ExplanationKey.netWorthDeep).select('trend'), 'down');
      expect(x.firstOf(ExplanationPart.deepTip), isNull);
    });
  });

  group('inflation', () {
    final basket = [
      InflationBasketPoint(2025, 6, e(10000)),
      InflationBasketPoint(2026, 3, e(12500)),
    ];

    test('basket start and end, change percent, tip category', () {
      final x = basic(
        InflationExplainInput(basket: basket, biggestRiseCategoryId: 'dining'),
      );
      final f = line(x, ExplanationKey.inflationBasic);
      expect(f.select('trend'), 'up');
      expect(f.money('startAmount'), e(10000));
      expect(f.money('endAmount'), e(12500));
      expect((f.args['percent']! as PercentArg).bp, 2500);
      expect(
        (line(x, ExplanationKey.inflationTip).args['category']! as CategoryArg)
            .categoryId,
        'dining',
      );
    });

    test('too few points, or a zero base: nothing', () {
      expect(
        basic(InflationExplainInput(basket: [basket.first])).isEmpty,
        isTrue,
      );
      expect(
        basic(
          InflationExplainInput(
            basket: [InflationBasketPoint(2025, 6, e(0)), basket.last],
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('deep: delivery sentence only when it rose', () {
      final up = deep(
        InflationExplainInput(
          basket: basket,
          deliveryNow: e(300),
          deliveryBefore: e(200),
          basketVisitsPerMonth: 4,
        ),
      );
      expect(line(up, ExplanationKey.inflationDeep).money('average'), e(300));
      final t = line(up, ExplanationKey.inflationDeepTip);
      expect(t.money('target'), e(1250));
      expect(t.money('yearly'), e(1250 * 48));
      final flat = deep(
        InflationExplainInput(
          basket: basket,
          deliveryNow: e(200),
          deliveryBefore: e(300),
        ),
      );
      expect(flat.firstOf(ExplanationPart.deepFact), isNull);
      expect(flat.firstOf(ExplanationPart.deepTip), isNull);
    });
  });

  group('tiers', () {
    final cur = cf(1000000, 700000);
    final prevPoint = cf(1000000, 800000);
    final burn = BurnCurve(
      cycle: Cycle(start: CivilDate(2026, 3, 1), end: CivilDate(2026, 3, 30)),
      elapsedDays: 5,
      cumulative: [for (var d = 1; d <= 5; d++) e(1000 * d)],
      budget: e(100000),
      projectedTotal: e(30000),
    );

    test('Free: basic keys only, whatever previous data is supplied', () {
      final withPrev = basic(
        CashFlowExplainInput(current: cur, previous: prevPoint),
        c: ExplainContext(burn: burn),
      );
      final without = basic(CashFlowExplainInput(current: cur));
      expect(withPrev.lines.map((l) => l.key), without.lines.map((l) => l.key));
      expect(withPrev.lines.any((l) => l.key.isDeepOnly), isFalse);
      expect(withPrev.offersDeepUpsell, isTrue);
    });

    test('Gold: no basic tip, deep parts appear, no upsell', () {
      final x = deep(CashFlowExplainInput(current: cur, previous: prevPoint));
      expect(x.firstOf(ExplanationPart.tip), isNull);
      expect(x.firstOf(ExplanationPart.deepFact), isNotNull);
      expect(x.offersDeepUpsell, isFalse);
    });

    test('tierFor maps the Gold flag', () {
      expect(tierFor(isGold: true), ExplanationTier.deep);
      expect(tierFor(isGold: false), ExplanationTier.basic);
    });

    test(
      'projection joins charts 1, 2, 3, 5, 7 only, when a budget exists',
      () {
        final ctx = ExplainContext(burn: burn);
        final x = deep(CashFlowExplainInput(current: cur), c: ctx);
        final pr = line(x, ExplanationKey.deepProjection);
        expect(pr.select('state'), 'other');
        expect(pr.money('projected'), e(30000));
        final noBudget = deep(
          CashFlowExplainInput(current: cur),
          c: ExplainContext(
            burn: BurnCurve(
              cycle: burn.cycle,
              elapsedDays: 5,
              cumulative: burn.cumulative,
              budget: null,
              projectedTotal: e(30000),
            ),
          ),
        );
        expect(noBudget.firstOf(ExplanationPart.projection), isNull);
        final subs = deep(
          SubscriptionsExplainInput(
            current: SubscriptionsAnnual(
              items: [
                SubscriptionCost(
                  itemId: 'a',
                  name: 'a',
                  amount: e(1),
                  annual: e(12),
                ),
              ],
              annualTotal: e(12),
            ),
          ),
          c: ctx,
        );
        expect(subs.firstOf(ExplanationPart.projection), isNull);
      },
    );

    test('drivers need three merchants that moved', () {
      MerchantSpend m(String n, int a) =>
          MerchantSpend(merchantNorm: n, name: n, amount: e(a), count: 1);
      final now = [m('a', 500), m('b', 300), m('c', 100)];
      final before = [m('a', 100), m('b', 290), m('c', 100)];
      final three = deep(
        CashFlowExplainInput(current: cur),
        c: ExplainContext(
          merchants: [...now, m('d', 50)],
          previousMerchants: before,
        ),
      );
      final d = line(three, ExplanationKey.deepDrivers);
      expect(
        [
          for (final k in ['merchant', 'merchant2', 'merchant3'])
            (d.args[k]! as NameArg).name,
        ],
        ['a', 'd', 'b'],
      );
      final two = deep(
        CashFlowExplainInput(current: cur),
        c: ExplainContext(merchants: now, previousMerchants: before),
      );
      expect(two.firstOf(ExplanationPart.drivers), isNull);
    });
  });

  group('needsDataFor', () {
    test('maps charts and reasons to the select branches', () {
      expect(
        needsDataFor(ChartId.netWorth, NotEnoughReason.noData),
        'accounts',
      );
      expect(
        needsDataFor(ChartId.installmentTimeline, NotEnoughReason.noData),
        'installments',
      );
      expect(
        needsDataFor(ChartId.subscriptionsAnnual, NotEnoughReason.noData),
        'subscriptions',
      );
      expect(
        needsDataFor(ChartId.monthVsAverage, NotEnoughReason.tooFewCycles),
        'months',
      );
      expect(needsDataFor(ChartId.cashFlow, NotEnoughReason.noData), 'cycle');
      expect(
        needsDataFor(ChartId.fiftyThirtyTwenty, NotEnoughReason.noIncome),
        'other',
      );
    });
  });

  group('copy deck keys', () {
    Map<String, Object?> arb(String lang) =>
        jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
            as Map<String, Object?>;

    test('every key the engine emits exists in both ARB files', () {
      for (final lang in ['en', 'ar']) {
        final a = arb(lang);
        for (final k in ExplanationKey.values) {
          expect(
            a.containsKey(k.l10nKey),
            isTrue,
            reason: '$lang ${k.l10nKey}',
          );
        }
      }
    });

    test('args the engine passes are placeholders of the ARB entry', () {
      final en = arb('en');
      final lines = <ExplanationLine>[];
      final ctx = ExplainContext();
      lines.addAll(
        deep(
          CashFlowExplainInput(current: cf(1000, 700), previous: cf(1000, 800)),
        ).lines,
      );
      lines.addAll(
        basic(
          CashFlowExplainInput(
            current: cf(1000, 1500),
            categories: [slice('dining', 900, 5000)],
          ),
        ).lines,
      );
      lines.addAll(
        basic(
          Rule503020ExplainInput(
            current: FiftyThirtyTwenty(
              income: e(1000),
              needs: e(500),
              wants: e(400),
              savings: e(100),
              other: e(0),
            ),
          ),
          c: ctx,
        ).lines,
      );
      expect(lines, isNotEmpty);
      for (final l in lines) {
        final meta = en['@${l.key.l10nKey}'] as Map<String, Object?>?;
        final ph = (meta?['placeholders'] as Map<String, Object?>? ?? {}).keys;
        for (final name in l.args.keys) {
          expect(ph, contains(name), reason: '${l.key.l10nKey}.$name');
        }
      }
    });
  });
}
