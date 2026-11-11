import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);

void main() {
  group('CivilDate', () {
    test('epoch, ISO, leap days, year 2100 and 1900', () {
      expect(d(1970, 1, 1).epochDay, 0);
      expect(d(2026, 11, 11).toIso(), '2026-11-11');
      expect(d(2024, 2, 29).plusDays(1), d(2024, 3, 1));
      expect(d(2100, 2, 28).plusDays(1), d(2100, 3, 1));
      expect(d(1900, 2, 28).plusDays(1), d(1900, 3, 1));
      expect(d(2000, 2, 28).plusDays(1), d(2000, 2, 29));
      expect(() => d(2100, 2, 29), throwsArgumentError);
      expect(d(2026, 12, 31).plusDays(1), d(2027, 1, 1));
      expect(d(2026, 3, 1).difference(d(2026, 2, 1)), 28);
    });
    test('tryParse is strict', () {
      expect(CivilDate.tryParse('2026-10-25'), d(2026, 10, 25));
      for (final bad in [
        '2026-1-25',
        '2026-02-30',
        '2026-13-01',
        '٢٠٢٦-١٠-٢٥',
        '2026-10-25 ',
        '',
      ]) {
        expect(CivilDate.tryParse(bad), isNull, reason: bad);
      }
    });
    test('fromLocalMs uses floor division and the stored offset', () {
      int utc(int y, int mo, int dd, int h, [int mi = 0]) =>
          DateTime.utc(y, mo, dd, h, mi).millisecondsSinceEpoch;
      // 22:00Z + 180 min is 01:00 of the next day.
      expect(CivilDate.fromLocalMs(utc(2025, 4, 24, 22), 180), d(2025, 4, 25));
      expect(CivilDate.fromLocalMs(utc(2025, 4, 24, 22), 120), d(2025, 4, 25));
      expect(
        CivilDate.fromLocalMs(utc(2025, 4, 24, 21, 59), 120),
        d(2025, 4, 24),
      );
      // Before the epoch (negative ms) still floors.
      expect(CivilDate.fromLocalMs(-1, 0), d(1969, 12, 31));
      expect(CivilDate.fromLocalMs(-1, 120), d(1970, 1, 1));
      // Negative offset.
      expect(CivilDate.fromLocalMs(utc(2026, 1, 1, 3), -300), d(2025, 12, 31));
    });
    test('round trip over 1900..2200', () {
      for (var e = d(1900, 1, 1).epochDay; e <= d(2200, 12, 31).epochDay; e++) {
        final c = CivilDate.fromEpochDay(e);
        expect(CivilDate(c.year, c.month, c.day).epochDay, e);
      }
    });
  });

  group('PaydaySchedule single era', () {
    test('payday 25 gives 25 Oct - 24 Nov', () {
      final c = PaydaySchedule.single(25).cycleOn(d(2026, 11, 10));
      expect(c.start, d(2026, 10, 25));
      expect(c.end, d(2026, 11, 24));
      expect(c.key, '2026-10-25');
      expect(c.length, 31);
    });
    test('A-43 default is day 1; February lengths', () {
      final s = PaydaySchedule.single(1);
      expect(s.cycleOn(d(2026, 2, 15)).length, 28);
      expect(s.cycleOn(d(2024, 2, 15)).length, 29);
      expect(s.cycleOn(d(2026, 12, 31)).end, d(2026, 12, 31));
    });
    test('payday 28 across February', () {
      final c = PaydaySchedule.single(28).cycleOn(d(2026, 3, 1));
      expect(c.start, d(2026, 2, 28));
      expect(c.end, d(2026, 3, 27));
    });
    test('dayNumber / daysRemaining: payday, last day, after end', () {
      final c = PaydaySchedule.single(25).cycleOn(d(2026, 11, 10));
      expect(c.dayNumber(c.start), 1);
      expect(c.daysRemaining(c.start), 31);
      expect(c.daysRemaining(c.end), 1);
      expect(c.daysRemaining(c.end.plusDays(5)), 1);
    });
    test('rejects payday outside 1..28', () {
      for (final bad in [0, 29, 30, 31, -1]) {
        expect(() => PaydayEra(null, bad), throwsArgumentError);
      }
    });
  });

  group('EC-21 payday change (today 10 Nov 2026, was 25)', () {
    final today = d(2026, 11, 10);
    final base = PaydaySchedule.single(25);

    test('to 1: current cycle 25 Oct - 30 Nov, next starts 1 Dec', () {
      final s = base.withChange(today, 1);
      final c = s.cycleOn(today);
      expect(c.start, d(2026, 10, 25));
      expect(c.end, d(2026, 11, 30));
      expect(s.after(c).start, d(2026, 12, 1));
      expect(s.after(s.after(c)).start, d(2027, 1, 1));
    });
    test('to 20: 25 Oct - 19 Nov, then 20 Nov', () {
      final s = base.withChange(today, 20);
      final c = s.cycleOn(today);
      expect(c.end, d(2026, 11, 19));
      expect(s.after(c).start, d(2026, 11, 20));
    });
    test('to the same day as today: closes 9 Nov, new cycle today', () {
      final s = base.withChange(today, 10);
      expect(s.cycleOn(d(2026, 11, 9)).end, d(2026, 11, 9));
      expect(s.cycleOn(today).start, today);
      expect(s.cycleOn(today).end, d(2026, 12, 9));
    });
    test('earlier cycles never move', () {
      final s = base.withChange(today, 1);
      expect(s.cycleOn(d(2026, 9, 30)), base.cycleOn(d(2026, 9, 30)));
      expect(s.cycleOn(d(2026, 10, 24)).start, d(2026, 9, 25));
    });
    test('two changes in one cycle: the last wins; same-day replaces', () {
      final s1 = base.withChange(d(2026, 11, 5), 1).withChange(today, 20);
      expect(s1.cycleOn(today).start, d(2026, 10, 25));
      expect(s1.cycleOn(today).end, d(2026, 11, 19));
      final s2 = base.withChange(today, 1).withChange(today, 20);
      expect(s2.eras.length, 2);
      expect(s2.cycleOn(today).end, d(2026, 11, 19));
    });
    test('changing to the current day is a no-op', () {
      expect(base.withChange(today, 25), base);
    });
    test('null first era rewrites history', () {
      final s = PaydaySchedule.single(25);
      expect(s.cycleOn(d(2025, 3, 10)).start, d(2025, 2, 25));
    });
    test('change that lands before the first match of the new era chains', () {
      // era (null,25), (10 Nov, 8), (12 Nov, 20): 10..11 Nov has no 8th.
      final s = PaydaySchedule([
        PaydayEra(null, 25),
        PaydayEra(d(2026, 11, 10), 8),
        PaydayEra(d(2026, 11, 12), 20),
      ]);
      expect(s.cycleOn(d(2026, 11, 11)).start, d(2026, 10, 25));
      expect(s.cycleOn(d(2026, 11, 11)).end, d(2026, 11, 19));
      expect(s.cycleOn(d(2026, 11, 20)).start, d(2026, 11, 20));
    });
    test('constructor rejects bad era lists', () {
      expect(() => PaydaySchedule([]), throwsArgumentError);
      expect(() => PaydaySchedule([PaydayEra(today, 1)]), throwsArgumentError);
      expect(
        () => PaydaySchedule([
          PaydayEra(null, 1),
          PaydayEra(today, 2),
          PaydayEra(today, 3),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('JSON (database-schema §2.8)', () {
    test('round trip and rejection', () {
      final s = PaydaySchedule.single(25).withChange(d(2026, 11, 10), 1);
      expect(
        s.toJson(),
        '[{"from":null,"day":25},{"from":"2026-11-10","day":1}]',
      );
      expect(PaydaySchedule.tryFromJson(s.toJson())!.eras, s.eras);
      for (final bad in [
        '',
        'x',
        '[]',
        '{}',
        '[{"from":null,"day":29}]',
        '[{"from":"2026-11-10","day":1}]',
        '[{"from":null,"day":"1"}]',
        '[{"from":null,"day":1,"x":2}]',
        '[{"from":null,"day":1},{"from":"2026-13-01","day":2}]',
      ]) {
        expect(PaydaySchedule.tryFromJson(bad), isNull, reason: bad);
      }
    });
  });

  group('properties', () {
    test('(a) every payday 1-28 x every month 2020-2030, 1900, 2100', () {
      final years = [1900, ...List.generate(11, (i) => 2020 + i), 2100];
      for (var day = 1; day <= 28; day++) {
        final s = PaydaySchedule.single(day);
        for (final y in years) {
          for (var m = 1; m <= 12; m++) {
            final c = s.cycleOn(d(y, m, day));
            expect(c.start, d(y, m, day));
            expect(c.start.day, day);
            expect(c.length, inInclusiveRange(28, 31));
            final next = s.after(c);
            expect(next.start, c.end.plusDays(1));
            expect(next.start.day, day);
            expect(s.before(c).end, c.start.plusDays(-1));
            expect(c.contains(c.end) && !c.contains(next.start), isTrue);
            // The day before payday is in the previous cycle.
            expect(s.cycleOn(c.start.plusDays(-1)).end, c.start.plusDays(-1));
          }
        }
      }
    });

    test('(b) random era lists: each date in exactly one cycle', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final eras = <PaydayEra>[PaydayEra(null, 1 + r.nextInt(28))];
        var from = d(2026, 1, 1);
        for (var i = r.nextInt(5); i > 0; i--) {
          from = from.plusDays(1 + r.nextInt(60));
          eras.add(PaydayEra(from, 1 + r.nextInt(28)));
        }
        final s = PaydaySchedule(eras);
        var date = d(2025, 10, 1);
        Cycle? prev;
        for (var i = 0; i < 700; i++, date = date.plusDays(1)) {
          final c = s.cycleOn(date);
          expect(
            c.start <= date && date <= c.end,
            isTrue,
            reason: '$seed $date',
          );
          expect(c.length, greaterThanOrEqualTo(1));
          if (prev != null) {
            if (c == prev) continue;
            expect(c.start, prev.end.plusDays(1), reason: '$seed $date');
          }
          // Cycle of its own start and end are itself.
          expect(s.cycleOn(c.start), c);
          expect(s.cycleOn(c.end), c);
          prev = c;
        }
      }
    });
  });
}
