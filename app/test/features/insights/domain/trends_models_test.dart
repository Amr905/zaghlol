// T-211: unit tests of the Trends pure functions (AC 1-3).

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/trends_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

Money egp(int minor) => Money(Currency.of('EGP'), minor);

void main() {
  group('heat buckets (AC 2)', () {
    test('quartile cut points of the non-zero days, zeros ignored', () {
      final daily = [0, 0, 100, 200, 300, 400, 500, 600, 700, 800, 0];
      expect(heatThresholds(daily), [200, 400, 600]);
    });

    test('no spending gives no cut points; levels are zero', () {
      expect(heatThresholds([0, 0]), isEmpty);
      expect(heatLevel(0, const []), 0);
    });

    test('a zero day is level 0, the rest 1..4 by cut point', () {
      const th = [300, 500, 700];
      expect(heatLevel(0, th), 0);
      expect(heatLevel(1, th), 1);
      expect(heatLevel(300, th), 1);
      expect(heatLevel(301, th), 2);
      expect(heatLevel(700, th), 3);
      expect(heatLevel(701, th), 4);
    });

    test('a single non-zero day', () {
      final th = heatThresholds([0, 500]);
      expect(heatLevel(500, th), 1);
    });
  });

  group('grid (AC 2, 3)', () {
    test('week rows start on Saturday; future days are not filled', () {
      // 25 Oct 2026 is a Sunday: one empty cell before it.
      final p = ChartPeriod(CivilDate(2026, 10, 25), CivilDate(2026, 11, 24));
      final daily = [for (var i = 0; i < 31; i++) i < 3 ? 100 * (i + 1) : 0];
      final g = buildHeatGrid(p, daily, CivilDate(2026, 11, 3));
      expect(g.leading, 1);
      expect(g.days.length, 31);
      expect(g.rows, 5);
      expect(g.days.first.level, greaterThan(0));
      expect(g.days[4].level, 0);
      expect(g.days[4].future, isFalse);
      expect(g.days[10].future, isTrue);
      expect(g.days[10].level, 0);
      expect(g.days[9].isToday, isTrue);
    });

    test('Saturday index', () {
      expect(saturdayIndex(CivilDate(2026, 10, 24)), 0);
      expect(saturdayIndex(CivilDate(2026, 10, 30)), 6);
    });
  });

  group('priciest weekday (AC 3)', () {
    DayHourPattern pattern(Map<int, int> m) => DayHourPattern(
      byWeekday: {
        for (var d = 1; d <= 7; d++)
          d: DayHourCell(spend: egp(m[d] ?? 0), count: 1),
      },
      byHour: {
        for (var h = 0; h < 24; h++) h: DayHourCell(spend: egp(0), count: 0),
      },
    );

    test('the highest weekday; omitted under two weeks', () {
      final p = pattern({5: 900, 1: 100});
      expect(priciestWeekday(p, elapsedDays: 14), 5);
      expect(priciestWeekday(p, elapsedDays: 13), isNull);
    });

    test('a tie goes to the earlier day of a Saturday-first week', () {
      expect(priciestWeekday(pattern({6: 500, 5: 500}), elapsedDays: 20), 6);
    });

    test('nothing spent gives no caption', () {
      expect(priciestWeekday(pattern({}), elapsedDays: 20), isNull);
    });
  });

  group('in and out (AC 1)', () {
    CashFlowPoint pt(int m, int income, int spend) => CashFlowPoint(
      period: ChartPeriod.month(2026, m),
      income: egp(income),
      spend: egp(spend),
      isPartial: false,
    );

    test('an empty month has no data; the open month is projected', () {
      final bars = inOutBars([
        pt(9, 0, 0),
        pt(10, 3000000, 2500000),
        pt(11, 3200000, 1000000),
      ], CivilDate(2026, 11, 10));
      expect(bars[0].hasData, isFalse);
      expect(bars[1].projected, isFalse);
      expect(bars[1].spendMinor, 2500000);
      expect(bars[2].projected, isTrue);
      expect(bars[2].spendMinor, 3000000);
      expect(bars[2].incomeMinor, 3200000);
    });

    test('before three days the open month is not projected', () {
      final bars = inOutBars([pt(11, 100, 50)], CivilDate(2026, 11, 2));
      expect(bars.single.projected, isFalse);
      expect(bars.single.spendMinor, 50);
    });
  });
}
