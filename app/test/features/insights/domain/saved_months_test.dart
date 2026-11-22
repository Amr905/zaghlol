// T-209: the "saved each month" bars (AC 3, 4 maths) and the Overview models.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:zaghlol/features/insights/domain/overview_models.dart';
import 'package:zaghlol/features/insights/domain/saved_months.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
Money m(int minor) => Money(egp, minor);

CashFlowPoint point(CivilDate from, CivilDate to, int income, int spend) =>
    CashFlowPoint(
      period: ChartPeriod(from, to),
      income: m(income),
      spend: m(spend),
      isPartial: false,
    );

void main() {
  test('net per bucket and the average of the complete ones', () {
    final points = [
      point(CivilDate(2026, 6, 1), CivilDate(2026, 6, 30), 3000, 1000),
      point(CivilDate(2026, 7, 1), CivilDate(2026, 7, 31), 3000, 3500),
      point(CivilDate(2026, 8, 1), CivilDate(2026, 8, 31), 3000, 1999),
    ];
    final s = savedMonths(points, CivilDate(2026, 11, 10));
    expect([for (final b in s.bars) b.netMinor], [2000, -500, 1001]);
    expect(s.bars.any((b) => b.projected), isFalse);
    // (2000 - 500 + 1001) / 3 = 833.67 -> 834
    expect(s.averageMinor, 834);
  });

  test('a negative average rounds half away from zero', () {
    final points = [
      point(CivilDate(2026, 6, 1), CivilDate(2026, 6, 30), 0, 1),
      point(CivilDate(2026, 7, 1), CivilDate(2026, 7, 31), 0, 2),
    ];
    // -3 / 2 = -1.5 -> -2
    expect(savedMonths(points, CivilDate(2026, 11, 10)).averageMinor, -2);
  });

  test('the open bucket is projected and left out of the average', () {
    final points = [
      point(CivilDate(2026, 10, 1), CivilDate(2026, 10, 31), 3000, 1000),
      // 10 days of 30 elapsed on 10 Nov: spend 1000 -> 3000 projected
      point(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30), 5000, 1000),
    ];
    final s = savedMonths(points, CivilDate(2026, 11, 10));
    expect(s.bars.last.projected, isTrue);
    expect(s.bars.last.netMinor, 5000 - 3000);
    expect(s.averageMinor, 2000);
  });

  test('the open bucket is not projected before 3 days', () {
    final points = [
      point(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30), 5000, 1000),
    ];
    final s = savedMonths(points, CivilDate(2026, 11, 2));
    expect(s.bars.single.projected, isFalse);
    expect(s.bars.single.netMinor, 4000);
    expect(s.averageMinor, isNull);
  });

  test('a closed period has no projected bar', () {
    final points = [
      point(CivilDate(2026, 6, 1), CivilDate(2026, 6, 30), 5000, 1000),
    ];
    final s = savedMonths(points, CivilDate(2026, 11, 2));
    expect(s.bars.single.projected, isFalse);
    expect(s.averageMinor, 4000);
  });

  group('rankedCategories', () {
    CategoryDonut donut(Map<String?, int> amounts) => CategoryDonut(
      total: m(amounts.values.fold(0, (a, b) => a + b)),
      slices: [
        for (final e in amounts.entries)
          CategorySlice(
            categoryId: e.key,
            amount: m(e.value),
            shareBp: 0,
            count: 1,
          ),
      ],
    );

    test('largest first, limited, with the previous same-days amount', () {
      final rows = rankedCategories(
        donut({'a': 100, 'b': 400, 'c': 300, 'd': 200, 'e': 50}),
        previous: donut({'b': 200, 'c': 300}),
        limit: 4,
      );
      expect([for (final r in rows) r.categoryId], ['b', 'c', 'd', 'a']);
      expect(rows[0].previousMinor, 200);
      expect(rows[0].change, const ChartChange(ChangeDirection.up, 100));
      expect(rows[1].change, ChartChange.same);
      expect(rows[2].change, ChartChange.none, reason: 'no baseline');
    });

    test('without a previous period nothing is compared', () {
      final rows = rankedCategories(donut({'a': 100}));
      expect(rows.single.change, ChartChange.none);
      expect(rows.single.previousMinor, 0);
    });
  });

  group('upcoming dues', () {
    UpcomingDue due(String id, int d, int amount) => UpcomingDue(
      itemId: id,
      name: id,
      kind: 'bill',
      date: CivilDate(2026, 11, d),
      amount: m(amount),
    );
    final all = [
      due('c', 20, 300),
      due('a', 12, 100),
      due('x', 5, 999),
      due('b', 15, 200),
      due('d', 28, 400),
    ];
    final today = CivilDate(2026, 11, 10);

    test('the next three on or after today, soonest first', () {
      expect([for (final d in nextDues(all, today)) d.itemId], ['a', 'b', 'c']);
    });

    test('the sum to the end of the period, in one currency', () {
      final s = duesUntil(all, today, CivilDate(2026, 11, 24), egp);
      expect(s.minor, 100 + 200 + 300);
      expect(s.currency, egp);
      expect(duesUntil(all, today, CivilDate(2026, 11, 9), egp).minor, 0);
    });
  });
}
