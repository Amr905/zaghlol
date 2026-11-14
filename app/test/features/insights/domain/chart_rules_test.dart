// T-105: the pure chart arithmetic. Synthetic numbers only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_rules.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');

void main() {
  group('mulDivRound / deltaBp', () {
    test('rounds half away from zero and survives big products', () {
      expect(mulDivRound(1, 1, 2), 1);
      expect(mulDivRound(-1, 1, 2), -1);
      expect(mulDivRound(10, 1, 3), 3);
      expect(mulDivRound(Money.maxMinor, 10000, Money.maxMinor), 10000);
      expect(() => mulDivRound(1, 1, 0), throwsArgumentError);
    });

    test('deltaBp: null on a zero base, signed otherwise', () {
      expect(deltaBp(100, 0), isNull);
      expect(deltaBp(150, 100), 5000);
      expect(deltaBp(50, 100), -5000);
      expect(deltaBp(0, 0), isNull);
    });
  });

  group('sharesBp', () {
    test('adds up to exactly 10000 (largest remainder)', () {
      final s = sharesBp([1, 1, 1]);
      expect(s.fold<int>(0, (a, b) => a + b), 10000);
      expect(s, [3334, 3333, 3333]);
    });

    test('zero total gives zeros; a zero amount gets zero', () {
      expect(sharesBp([0, 0]), [0, 0]);
      expect(sharesBp([100, 0]), [10000, 0]);
      expect(sharesBp(const []), isEmpty);
    });

    test('huge amounts do not overflow', () {
      final s = sharesBp([Money.maxMinor, Money.maxMinor]);
      expect(s, [5000, 5000]);
    });
  });

  test('medianMinor: odd, even (floor of the mean), single', () {
    expect(medianMinor([5]), 5);
    expect(medianMinor([9, 1, 5]), 5);
    expect(medianMinor([1, 2]), 1);
    expect(medianMinor([2, 4, 6, 100]), 5);
    expect(() => medianMinor([]), throwsArgumentError);
  });

  test('isoWeekday: 1970-01-01 is Thursday, Monday=1, Sunday=7', () {
    expect(isoWeekday(0), 4);
    expect(isoWeekday(CivilDate(2026, 11, 9).epochDay), 1); // Monday
    expect(isoWeekday(CivilDate(2026, 11, 15).epochDay), 7); // Sunday
    expect(isoWeekday(CivilDate(2026, 11, 14).epochDay), 6); // Saturday
  });

  group('annualCost', () {
    final hundred = Money(egp, 10000);
    test('monthly x12, yearly x1, weekly x52', () {
      expect(annualCost(hundred, RecurrenceCadence.monthly).minor, 120000);
      expect(annualCost(hundred, RecurrenceCadence.yearly).minor, 10000);
      expect(annualCost(hundred, RecurrenceCadence.weekly).minor, 520000);
    });
    test('custom days: x365/N rounded half up', () {
      expect(
        annualCost(hundred, RecurrenceCadence.customDays, days: 10).minor,
        365000,
      );
      expect(
        annualCost(Money(egp, 1), RecurrenceCadence.customDays, days: 2).minor,
        183, // 182.5 -> 183
      );
      expect(
        () => annualCost(hundred, RecurrenceCadence.customDays),
        throwsArgumentError,
      );
    });
  });

  test('projectLinear: straight line, rounded half up', () {
    expect(projectLinear(Money(egp, 1000), 10, 30).minor, 3000);
    expect(projectLinear(Money(egp, 1), 3, 10).minor, 3); // 3.33
    expect(() => projectLinear(Money(egp, 1), 0, 10), throwsArgumentError);
  });

  group('personalInflation', () {
    int m(int y, int mo) => y * 12 + mo - 1;
    test('median ratio per month against each merchant first month', () {
      final pts = [
        // a: 100 -> 110 -> 120
        PricePoint('a', m(2026, 1), 10000),
        PricePoint('a', m(2026, 2), 11000),
        PricePoint('a', m(2026, 3), 12000),
        // b: 200 -> 200 -> 220
        PricePoint('b', m(2026, 1), 20000),
        PricePoint('b', m(2026, 2), 20000),
        PricePoint('b', m(2026, 3), 22000),
        // c: 50 -> 60 -> 55
        PricePoint('c', m(2026, 1), 5000),
        PricePoint('c', m(2026, 2), 6000),
        PricePoint('c', m(2026, 3), 5500),
        // d: seen once only: ignored
        PricePoint('d', m(2026, 3), 99999),
      ];
      final out = personalInflation(pts);
      expect([for (final p in out) p.indexBp], [10000, 11000, 11000]);
      expect(out.first.month, 1);
      expect(out.last.merchants, 3);
    });

    test('a month uses the median purchase of that month', () {
      final pts = [
        for (final a in [100, 300, 200]) PricePoint('a', 0, a * 100),
        PricePoint('a', 1, 22000),
        for (final k in ['b', 'c']) ...[
          PricePoint(k, 0, 20000),
          PricePoint(k, 1, 20000),
        ],
      ];
      final out = personalInflation(pts);
      // a: median 20000 -> 22000 = 11000; b, c = 10000; median 10000.
      expect(out[1].indexBp, 10000);
    });

    test('fewer than 3 repeated merchants gives nothing', () {
      expect(
        personalInflation([
          PricePoint('a', 0, 100),
          PricePoint('a', 1, 110),
          PricePoint('b', 0, 100),
          PricePoint('b', 1, 110),
        ]),
        isEmpty,
      );
    });

    test('zero and negative prices are ignored', () {
      expect(
        personalInflation([
          for (final k in ['a', 'b', 'c']) ...[
            PricePoint(k, 0, 0),
            PricePoint(k, 1, -5),
          ],
        ]),
        isEmpty,
      );
    });

    test('a month with fewer than 3 contributors is skipped', () {
      final pts = [
        for (final k in ['a', 'b', 'c']) PricePoint(k, 0, 1000),
        for (final k in ['a', 'b']) PricePoint(k, 1, 1100),
        for (final k in ['a', 'b', 'c']) PricePoint(k, 2, 1200),
      ];
      expect([for (final p in personalInflation(pts)) p.month], [1, 3]);
    });
  });

  group('dueDatesInWindow', () {
    List<String> run({
      required CivilDate next,
      RecurrenceCadence cadence = RecurrenceCadence.monthly,
      int? dueDay,
      int? days,
      int? remaining,
      int y = 2026,
      int mo = 11,
      int months = 6,
    }) => [
      for (final d in dueDatesInWindow(
        next: next,
        cadence: cadence,
        dueDay: dueDay,
        days: days,
        remaining: remaining,
        firstYear: y,
        firstMonth: mo,
        months: months,
      ))
        '${d.date.toIso()}${d.overdue ? '!' : ''}',
    ];

    test('monthly day 31 clamps to short months and keeps the anchor', () {
      expect(run(next: CivilDate(2026, 11, 30), dueDay: 31, months: 5), [
        '2026-11-30',
        '2026-12-31',
        '2027-01-31',
        '2027-02-28',
        '2027-03-31',
      ]);
    });

    test('remaining caps the count; zero remaining gives none', () {
      expect(run(next: CivilDate(2026, 11, 5), remaining: 2), [
        '2026-11-05',
        '2026-12-05',
      ]);
      expect(run(next: CivilDate(2026, 11, 5), remaining: 0), isEmpty);
    });

    test('overdue dates are flagged and kept', () {
      expect(run(next: CivilDate(2026, 10, 20), months: 2), [
        '2026-10-20!',
        '2026-11-20',
        '2026-12-20',
      ]);
    });

    test('window crosses the year end', () {
      final r = run(next: CivilDate(2026, 12, 15), y: 2026, mo: 12, months: 2);
      expect(r, ['2026-12-15', '2027-01-15']);
    });

    test('weekly and custom days step in days', () {
      expect(
        run(
          next: CivilDate(2026, 11, 1),
          cadence: RecurrenceCadence.weekly,
          months: 1,
        ).length,
        5,
      );
      expect(
        run(
          next: CivilDate(2026, 11, 1),
          cadence: RecurrenceCadence.customDays,
          days: 15,
          months: 1,
        ),
        ['2026-11-01', '2026-11-16'],
      );
    });
  });

  group('ChartPeriod', () {
    test('month and cycle factories, validation', () {
      final feb = ChartPeriod.month(2028, 2);
      expect(feb.lengthDays, 29);
      expect(feb.contains(CivilDate(2028, 2, 29)), isTrue);
      expect(feb.contains(CivilDate(2028, 3, 1)), isFalse);
      expect(
        () => ChartPeriod(CivilDate(2026, 2, 2), CivilDate(2026, 2, 1)),
        throwsArgumentError,
      );
      expect(
        ChartPeriod.cycle(
          PaydaySchedule.single(25).cycleOn(CivilDate(2026, 11, 10)),
        ).key,
        '2026-10-25..2026-11-24',
      );
    });
  });
}
