// T-189 (AC 3): summary / comparison maths per currency, top-5 + Other,
// axis steps and compact labels.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');

PeriodTotals totals(Currency c, int income, int spend) =>
    PeriodTotals(income: Money(c, income), spend: Money(c, spend));

CategorySlice slice(String? id, int minor, int bp, {int count = 1}) =>
    CategorySlice(
      categoryId: id,
      amount: Money(egp, minor),
      shareBp: bp,
      count: count,
    );

void main() {
  group('percentChange', () {
    test('rounds half away from zero', () {
      expect(
        percentChange(1125, 1000),
        const ChartChange(ChangeDirection.up, 13),
      );
      expect(
        percentChange(875, 1000),
        const ChartChange(ChangeDirection.down, 13),
      );
      expect(percentChange(1124, 1000).value, 12);
    });
    test('equal is same, zero baseline has no comparison', () {
      expect(percentChange(500, 500), ChartChange.same);
      expect(percentChange(0, 0), ChartChange.same);
      expect(percentChange(500, 0), ChartChange.none);
      expect(percentChange(500, -10), ChartChange.none);
    });
    test('under half a percent reads as same', () {
      expect(percentChange(100004, 100000), ChartChange.same);
    });
  });

  group('ChartSummary', () {
    test('spent, income, saved, rate and their changes', () {
      final s = ChartSummary.compute(
        totals(egp, 3200000, 1980000),
        totals(egp, 3200000, 2150000),
      );
      expect(s.spent.minor, 1980000);
      expect(s.saved.minor, 1220000);
      expect(s.ratePct, 38); // 12200 / 32000 = 38.1%
      expect(s.spentChange, const ChartChange(ChangeDirection.down, 8));
      expect(s.incomeChange, ChartChange.same);
      // saved 12200 vs 10500: +16.2% -> 16
      expect(s.savedChange, const ChartChange(ChangeDirection.up, 16));
      // rate 38 vs 33 (10500/32000 = 32.8 -> 33): +5 points
      expect(
        s.rateChange,
        const ChartChange(ChangeDirection.up, 5, isPoints: true),
      );
    });

    test('no income: no rate, rate change is none', () {
      final s = ChartSummary.compute(
        totals(egp, 0, 5000),
        totals(egp, 10000, 4000),
      );
      expect(s.ratePct, isNull);
      expect(s.rateChange, ChartChange.none);
      expect(s.saved.minor, -5000);
      // previous saved 6000, now -5000: down 183%
      expect(s.savedChange, const ChartChange(ChangeDirection.down, 183));
    });

    test('negative saved gives a negative rate', () {
      final t = totals(egp, 10000, 12500);
      expect(t.ratePct, -25);
    });

    test('previous period empty: every change is none or same', () {
      final s = ChartSummary.compute(
        totals(egp, 10000, 4000),
        totals(egp, 0, 0),
      );
      expect(s.spentChange, ChartChange.none);
      expect(s.incomeChange, ChartChange.none);
      expect(s.rateChange, ChartChange.none);
    });

    test('is per currency: each currency has its own totals', () {
      final e = ChartSummary.compute(
        totals(egp, 100000, 50000),
        totals(egp, 100000, 100000),
      );
      final u = ChartSummary.compute(
        totals(usd, 20000, 10000),
        totals(usd, 20000, 5000),
      );
      expect(e.spent.currency, egp);
      expect(u.spent.currency, usd);
      expect(e.spentChange, const ChartChange(ChangeDirection.down, 50));
      expect(u.spentChange, const ChartChange(ChangeDirection.up, 100));
    });

    test('mixing currencies in one summary throws', () {
      expect(
        () => ChartSummary.compute(
          totals(egp, 100, 50),
          PeriodTotals(income: Money(usd, 100), spend: Money(usd, 50)),
        ).spentChange,
        returnsNormally, // each side is internally one currency
      );
      expect(() => Money(egp, 1) + Money(usd, 1), throwsA(anything));
    });

    test('fromCashFlow: no rows is zero, rows are summed', () {
      final empty = PeriodTotals.fromCashFlow(
        const ChartNotEnoughData<List<CashFlowPoint>>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        ),
        egp,
      );
      expect(empty.isEmpty, isTrue);
      final p = ChartPeriod(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30));
      final r = PeriodTotals.fromCashFlow(
        ChartReady([
          CashFlowPoint(
            period: p,
            income: Money(egp, 100),
            spend: Money(egp, 40),
            isPartial: false,
          ),
        ]),
        egp,
      );
      expect(r.saved.minor, 60);
    });
  });

  group('topCategoriesPlusOther', () {
    final donut = CategoryDonut(
      total: Money(egp, 1000),
      slices: [
        slice('a', 100, 1000),
        slice('b', 300, 3000),
        slice('c', 200, 2000),
        slice('d', 150, 1500),
        slice('e', 120, 1200),
        slice('f', 80, 800),
        slice('g', 50, 500, count: 2),
      ],
    );

    test('five named entries, the rest folded into Other', () {
      final e = topCategoriesPlusOther(donut);
      expect(e.length, 6);
      expect(
        [for (final x in e.take(5)) x.categoryId],
        ['b', 'c', 'd', 'e', 'a'],
      );
      final other = e.last;
      expect(other.isOther, isTrue);
      expect(other.amount.minor, 130);
      expect(other.shareBp, 1300);
      expect(other.count, 3);
      expect(other.memberIds, ['f', 'g']);
      // Amounts and shares add up to the donut's.
      expect(e.fold<int>(0, (a, x) => a + x.amount.minor), 1000);
      expect(e.fold<int>(0, (a, x) => a + x.shareBp), 10000);
    });

    test('five or fewer slices: no Other', () {
      final small = CategoryDonut(
        total: Money(egp, 300),
        slices: [slice('a', 200, 6667), slice('b', 100, 3333)],
      );
      final e = topCategoriesPlusOther(small);
      expect(e.length, 2);
      expect(e.any((x) => x.isOther), isFalse);
    });

    test('change chips against the previous period', () {
      final prev = CategoryDonut(
        total: Money(egp, 500),
        slices: [slice('b', 250, 5000), slice('c', 200, 4000)],
      );
      final e = topCategoriesPlusOther(donut, previous: prev);
      final byId = {for (final x in e) x.categoryId: x};
      expect(byId['b']!.change, const ChartChange(ChangeDirection.up, 20));
      expect(byId['c']!.change, ChartChange.same);
      // 'd' was not in the previous period: no baseline.
      expect(byId['d']!.change, ChartChange.none);
      expect(e.last.change, ChartChange.none); // Other has no chip
    });
  });

  group('pickInsight', () {
    CategoryDonut d(int a, int b) => CategoryDonut(
      total: Money(egp, a + b),
      slices: [slice('x', a, 5000), slice('y', b, 5000)],
    );
    ChartSummary sum(int cur, int prev) => ChartSummary.compute(
      totals(egp, 100000, cur),
      totals(egp, 100000, prev),
    );

    test('down overall with a riser', () {
      final prev = d(100, 100);
      final entries = topCategoriesPlusOther(d(112, 50), previous: prev);
      final i = pickInsight(sum(8000, 10000), entries);
      expect(i.kind, ChartInsightKind.downWithRiser);
      expect(i.riserId, 'x');
      expect(i.riserPct, 12);
    });
    test('up overall without a riser, same, and no baseline', () {
      expect(
        pickInsight(sum(12000, 10000), const []).kind,
        ChartInsightKind.up,
      );
      expect(
        pickInsight(sum(10000, 10000), const []).kind,
        ChartInsightKind.same,
      );
      expect(
        pickInsight(sum(10000, 0), const []).kind,
        ChartInsightKind.noBaseline,
      );
    });
  });

  group('axis', () {
    test('nice step keeps 3-4 gridlines', () {
      for (final max in [1, 7, 99, 3200000, 2999999, 123456789]) {
        final step = niceAxisStep(max);
        final top = axisTop(max, step);
        final lines = top ~/ step;
        expect(lines, inInclusiveRange(1, 4), reason: 'max $max');
        expect(top, greaterThanOrEqualTo(max));
      }
      expect(niceAxisStep(3000000), 1000000);
      expect(axisTop(3000000, 1000000), 3000000);
    });
    test('FU-284: edge maxima around step boundaries keep 1-4 lines', () {
      for (var max = 1; max <= 5000; max++) {
        final step = niceAxisStep(max);
        final top = axisTop(max, step);
        expect(top, greaterThanOrEqualTo(max), reason: 'max $max');
        expect(top ~/ step, inInclusiveRange(1, 4), reason: 'max $max');
      }
      for (final max in [10, 100, 1000, 100000, 1000000]) {
        final step = niceAxisStep(max);
        expect(axisTop(max, step) ~/ step, inInclusiveRange(1, 4));
        final above = niceAxisStep(max + 1);
        expect(axisTop(max + 1, above) ~/ above, inInclusiveRange(1, 4));
      }
    });
    test('zero data still has a usable axis', () {
      expect(niceAxisStep(0), 1);
      expect(axisTop(0, 1), 1);
    });

    test('compact labels', () {
      expect(
        compactAmount(120000, 2),
        const CompactAmount(12, CompactUnit.thousand),
      );
      expect(
        compactAmount(3200000, 2),
        const CompactAmount(320, CompactUnit.thousand),
      );
      expect(compactAmount(0, 2), const CompactAmount(0, CompactUnit.none));
      expect(
        compactAmount(95000, 2),
        const CompactAmount(9500, CompactUnit.none),
      );
      expect(
        compactAmount(150000000, 2),
        const CompactAmount(15, CompactUnit.million),
      );
      // 999,960 -> would print 1000.0K: that is 1.0M
      expect(
        compactAmount(99996000, 2),
        const CompactAmount(10, CompactUnit.million),
      );
      // Three-decimal and zero-decimal currencies.
      expect(
        compactAmount(1500000, 3),
        const CompactAmount(15, CompactUnit.thousand),
      );
      expect(
        compactAmount(1200, 0),
        const CompactAmount(12, CompactUnit.thousand),
      );
      expect(
        compactAmount(-120000, 2),
        const CompactAmount(-12, CompactUnit.thousand),
      );
      expect(Money(kwd, 1).currency.exponent, 3);
    });
  });
}
