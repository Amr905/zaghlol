// T-188 AC1/AC2: every preset and a custom range resolve across month ends,
// payday cycles, leap years and Ramadan dates; stepping stops at today.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);
ChartPeriod p(CivilDate a, CivilDate b) => ChartPeriod(a, b);

final p25 = PaydaySchedule.single(25);
final p1 = PaydaySchedule.single(1);

ChartPeriod res(
  ChartPeriodSelection s,
  CivilDate today, [
  PaydaySchedule? schedule,
]) => s.resolve(today, schedule ?? p25);

void main() {
  group('cycle presets (payday cycles)', () {
    test('this and last cycle, payday 25', () {
      final today = d(2026, 11, 10);
      expect(
        res(ChartPeriodSelection.thisCycle, today),
        p(d(2026, 10, 25), d(2026, 11, 24)),
      );
      expect(
        res(const ChartPeriodSelection(ChartPreset.lastCycle), today),
        p(d(2026, 9, 25), d(2026, 10, 24)),
      );
    });

    test('the payday itself starts the new cycle; the day before is old', () {
      expect(
        res(ChartPeriodSelection.thisCycle, d(2026, 11, 25)),
        p(d(2026, 11, 25), d(2026, 12, 24)),
      );
      expect(
        res(ChartPeriodSelection.thisCycle, d(2026, 11, 24)),
        p(d(2026, 10, 25), d(2026, 11, 24)),
      );
    });

    test('payday 28 across February of a leap and a normal year', () {
      final s = PaydaySchedule.single(28);
      expect(
        res(ChartPeriodSelection.thisCycle, d(2024, 3, 5), s),
        p(d(2024, 2, 28), d(2024, 3, 27)),
      );
      expect(
        res(ChartPeriodSelection.thisCycle, d(2025, 2, 28), s),
        p(d(2025, 2, 28), d(2025, 3, 27)),
      );
    });

    test('payday 1 is the calendar month', () {
      expect(
        res(ChartPeriodSelection.thisCycle, d(2026, 2, 28), p1),
        p(d(2026, 2, 1), d(2026, 2, 28)),
      );
    });

    test('a payday change (eras) is honoured when stepping back', () {
      final s = PaydaySchedule([
        PaydayEra(null, 25),
        PaydayEra(d(2026, 9, 1), 1),
      ]);
      final today = d(2026, 11, 10);
      expect(
        res(ChartPeriodSelection.thisCycle, today, s),
        p(d(2026, 11, 1), d(2026, 11, 30)),
      );
      final back2 = const ChartPeriodSelection(
        ChartPreset.thisCycle,
        offset: 2,
      );
      // Sep 1 era start: the cycle before Oct 1 is Sep 1..Sep 30, then the
      // old-era cycle that ended on Aug 31.
      expect(res(back2, today, s), p(d(2026, 9, 1), d(2026, 9, 30)));
      final back3 = const ChartPeriodSelection(
        ChartPreset.thisCycle,
        offset: 3,
      );
      expect(res(back3, today, s).to, d(2026, 8, 31));
    });

    test('stepping from last cycle goes to two cycles ago', () {
      final s = const ChartPeriodSelection(ChartPreset.lastCycle).stepped(1);
      expect(res(s, d(2026, 11, 10)), p(d(2026, 8, 25), d(2026, 9, 24)));
      expect(s.preset, ChartPreset.lastCycle);
    });
  });

  group('month presets', () {
    test('this and last month at month ends and year boundary', () {
      expect(
        res(const ChartPeriodSelection(ChartPreset.thisMonth), d(2026, 1, 31)),
        p(d(2026, 1, 1), d(2026, 1, 31)),
      );
      expect(
        res(const ChartPeriodSelection(ChartPreset.lastMonth), d(2026, 1, 31)),
        p(d(2025, 12, 1), d(2025, 12, 31)),
      );
    });

    test('last month from 31 March is a short February (leap and not)', () {
      const s = ChartPeriodSelection(ChartPreset.lastMonth);
      expect(res(s, d(2024, 3, 31)), p(d(2024, 2, 1), d(2024, 2, 29)));
      expect(res(s, d(2026, 3, 31)), p(d(2026, 2, 1), d(2026, 2, 28)));
    });
  });

  group('rolling presets', () {
    test('last 3 months ends today and starts on the 1st', () {
      const s = ChartPeriodSelection(ChartPreset.last3Months);
      expect(res(s, d(2026, 11, 10)), p(d(2026, 9, 1), d(2026, 11, 10)));
      expect(res(s, d(2026, 1, 31)), p(d(2025, 11, 1), d(2026, 1, 31)));
    });

    test('last 12 months on a leap day', () {
      const s = ChartPeriodSelection(ChartPreset.last12Months);
      expect(res(s, d(2024, 2, 29)), p(d(2023, 3, 1), d(2024, 2, 29)));
    });

    test('stepping gives contiguous full blocks', () {
      const s = ChartPeriodSelection(ChartPreset.last3Months);
      final today = d(2026, 11, 10);
      final b1 = res(s.stepped(1), today);
      final b2 = res(s.stepped(2), today);
      expect(b1, p(d(2026, 6, 1), d(2026, 8, 31)));
      expect(b2, p(d(2026, 3, 1), d(2026, 5, 31)));
      expect(res(s, today).from.difference(b1.to), 1);
    });

    test('last 6 months', () {
      const s = ChartPeriodSelection(ChartPreset.last6Months);
      expect(res(s, d(2026, 11, 10)), p(d(2026, 6, 1), d(2026, 11, 10)));
      expect(
        res(s.stepped(1), d(2026, 11, 10)),
        p(d(2025, 12, 1), d(2026, 5, 31)),
      );
    });
  });

  group('this year', () {
    test('full year, leap year, and stepping back', () {
      const s = ChartPeriodSelection(ChartPreset.thisYear);
      expect(res(s, d(2024, 6, 1)), p(d(2024, 1, 1), d(2024, 12, 31)));
      expect(
        res(s.stepped(1), d(2024, 6, 1)),
        p(d(2023, 1, 1), d(2023, 12, 31)),
      );
      expect(res(s, d(2024, 6, 1)).lengthDays, 366);
    });
  });

  group('custom range', () {
    test('resolves as given; stepping shifts by its own length', () {
      // Ramadan 1447 (about 18 Feb to 19 Mar 2026), over a month end.
      final s = ChartPeriodSelection.custom(d(2026, 2, 18), d(2026, 3, 19));
      final today = d(2026, 11, 10);
      expect(res(s, today), p(d(2026, 2, 18), d(2026, 3, 19)));
      expect(res(s.stepped(1), today), p(d(2026, 1, 19), d(2026, 2, 17)));
      expect(res(s.stepped(-1), today), p(d(2026, 3, 20), d(2026, 4, 18)));
    });

    test('a range over 29 February keeps its length when stepped', () {
      final s = ChartPeriodSelection.custom(d(2024, 2, 20), d(2024, 3, 5));
      final back = res(s.stepped(1), d(2026, 1, 1));
      expect(back.lengthDays, 15);
      expect(back.to, d(2024, 2, 19));
    });

    test('rejects an inverted or over-long range', () {
      expect(
        () => ChartPeriodSelection.custom(d(2026, 3, 1), d(2026, 2, 1)),
        throwsArgumentError,
      );
      expect(
        () => ChartPeriodSelection.custom(d(2020, 1, 1), d(2026, 1, 1)),
        throwsArgumentError,
      );
      // Exactly the limit is fine.
      final from = d(
        2026,
        1,
        1,
      ).plusDays(-(ChartPeriodLimits.maxCustomDays - 1));
      expect(ChartPeriodSelection.custom(from, d(2026, 1, 1)).customFrom, from);
    });
  });

  group('stepping stops at today (AC2)', () {
    final today = d(2026, 11, 10);
    ChartPeriodSelection back(ChartPeriodSelection s) => s.stepped(1);

    test('current periods cannot step forward, past ones can, then stop', () {
      for (final preset in const [
        ChartPreset.thisCycle,
        ChartPreset.thisMonth,
        ChartPreset.last3Months,
        ChartPreset.last6Months,
        ChartPreset.last12Months,
        ChartPreset.thisYear,
      ]) {
        final s = ChartPeriodSelection(preset);
        expect(s.canStepForward(today, p25), isFalse, reason: '$preset now');
        final b = back(s);
        expect(b.canStepForward(today, p25), isTrue, reason: '$preset back');
        expect(b.stepped(-1), s);
        expect(b.stepped(-1).canStepForward(today, p25), isFalse);
      }
    });

    test('last cycle / last month step forward once to the current one', () {
      for (final preset in const [
        ChartPreset.lastCycle,
        ChartPreset.lastMonth,
      ]) {
        final s = ChartPeriodSelection(preset);
        expect(s.canStepForward(today, p25), isTrue);
        final now = s.stepped(-1);
        expect(now.periodsBack, 0);
        expect(now.canStepForward(today, p25), isFalse);
      }
    });

    test('custom range: forward while the next range has started', () {
      final s = ChartPeriodSelection.custom(d(2026, 10, 1), d(2026, 10, 31));
      expect(s.canStepForward(today, p25), isTrue); // Nov 1..Nov 30 started
      final next = s.stepped(-1);
      expect(next.canStepForward(today, p25), isFalse); // Dec 1.. is future
      final late = ChartPeriodSelection.custom(d(2026, 11, 1), d(2026, 11, 10));
      expect(late.canStepForward(today, p25), isFalse);
    });

    test('step back stops at the earliest date and offset limit', () {
      const s = ChartPeriodSelection(ChartPreset.thisYear);
      var cur = s;
      var n = 0;
      while (cur.canStepBack(today, p25)) {
        cur = cur.stepped(1);
        n++;
        expect(n, lessThan(200));
      }
      expect(cur.resolve(today, p25).from.year, greaterThanOrEqualTo(2000));
      expect(n, lessThanOrEqualTo(ChartPeriodLimits.maxOffset));
    });
  });

  group('resolveAll', () {
    test('previous is the same elapsed days of the period before (F2)', () {
      final r = ChartPeriodSelection.thisCycle.resolveAll(d(2026, 11, 10), p25);
      expect(r.period, p(d(2026, 10, 25), d(2026, 11, 24)));
      // 17 days elapsed: 25 Oct .. 10 Nov against 25 Sep .. 11 Oct.
      expect(r.previous, p(d(2026, 9, 25), d(2026, 10, 11)));
      expect(r.previousFull, p(d(2026, 9, 25), d(2026, 10, 24)));
      expect(r.previousCapped, isTrue);
      expect(r.cycle, Cycle(start: d(2026, 10, 25), end: d(2026, 11, 24)));
      expect(r.isCurrentCycle, isTrue);
      expect(r.canStepForward, isFalse);
      expect(r.canStepBack, isTrue);
    });

    test(
      'capping covers month, rolling and year; closed periods are whole',
      () {
        final today = d(2026, 11, 20);
        final m = const ChartPeriodSelection(ChartPreset.thisMonth)
            .resolveAll(today, p25);
        expect(m.previous, p(d(2026, 10, 1), d(2026, 10, 20)));
        final r = const ChartPeriodSelection(ChartPreset.last3Months)
            .resolveAll(today, p25);
        expect(r.period, p(d(2026, 9, 1), d(2026, 11, 20)));
        expect(r.previous.lengthDays, r.period.lengthDays);
        expect(r.previous.from, d(2026, 6, 1));
        final y = const ChartPeriodSelection(ChartPreset.thisYear)
            .resolveAll(today, p25);
        expect(y.previous, p(d(2025, 1, 1), d(2025, 11, 20)));
        final last = const ChartPeriodSelection(ChartPreset.lastMonth)
            .resolveAll(today, p25);
        expect(last.previous, p(d(2026, 9, 1), d(2026, 9, 30)));
        expect(last.previousCapped, isFalse);
        final back = const ChartPeriodSelection(
          ChartPreset.thisCycle,
          offset: 1,
        ).resolveAll(today, p25);
        expect(back.previousCapped, isFalse);
      },
    );

    test('a relative preset follows the date (re-resolves)', () {
      const s = ChartPeriodSelection(ChartPreset.thisMonth);
      expect(s.resolveAll(d(2026, 11, 30), p25).period.from, d(2026, 11, 1));
      expect(s.resolveAll(d(2026, 12, 1), p25).period.from, d(2026, 12, 1));
    });

    test(
      'burn rate and vs-average need a cycle; budget and the rest are fixed',
      () {
        final cyc = ChartPeriodSelection.thisCycle.resolveAll(
          d(2026, 11, 10),
          p25,
        );
        final mon = const ChartPeriodSelection(ChartPreset.thisMonth)
            .resolveAll(d(2026, 11, 10), p25);
        expect(cyc.supports(ChartId.burnCurve), isTrue);
        expect(mon.supports(ChartId.burnCurve), isFalse);
        expect(mon.supports(ChartId.monthVsAverage), isFalse);
        expect(mon.supports(ChartId.cashFlow), isTrue);
        expect(mon.supports(ChartId.categoryDonut), isTrue);
        expect(
          chartPeriodSupport(ChartId.subscriptionsAnnual),
          ChartPeriodSupport.fixed,
        );
        expect(mon.isCurrentCycle, isFalse);
      },
    );
  });

  group('storage codec', () {
    test('round trips every preset and a custom range', () {
      for (final preset in ChartPreset.values) {
        final s = preset == ChartPreset.custom
            ? ChartPeriodSelection.custom(
                d(2026, 2, 18),
                d(2026, 3, 19),
                offset: 2,
              )
            : ChartPeriodSelection(
                preset,
                offset: preset == ChartPreset.thisCycle ? 3 : 0,
              );
        expect(
          ChartPeriodSelection.tryDecode(s.encode()),
          s,
          reason: '$preset',
        );
      }
      expect(ChartPeriodSelection.thisCycle.encode(), 'thisCycle|0||');
    });

    test('anything else decodes to null', () {
      for (final bad in const [
        '',
        'thisCycle',
        'nope|0||',
        'thisCycle|x||',
        'thisCycle|1000||',
        'thisCycle|-13||',
        'thisCycle|0|2026-01-01|2026-02-01',
        'custom|0||',
        'custom|0|2026-02-30|2026-03-01',
        'custom|0|2026-03-01|2026-02-01',
        'custom|0|2000-01-01|2026-01-01',
        'thisCycle|0||||',
      ]) {
        expect(ChartPeriodSelection.tryDecode(bad), isNull, reason: bad);
      }
      expect(ChartPeriodSelection.tryDecode('x' * 100), isNull);
    });
  });

  group('buckets', () {
    final today = d(2030, 1, 1);

    test('kind follows the length', () {
      expect(
        bucketKindFor(p(d(2026, 1, 1), d(2026, 1, 31))),
        ChartBucketKind.day,
      );
      expect(
        bucketKindFor(p(d(2026, 1, 1), d(2026, 2, 1))),
        ChartBucketKind.week,
      );
      final six = p(d(2026, 1, 1), d(2026, 1, 1).plusDays(189));
      expect(bucketKindFor(six), ChartBucketKind.week);
      expect(
        bucketKindFor(p(d(2026, 1, 1), d(2026, 1, 1).plusDays(190))),
        ChartBucketKind.month,
      );
    });

    void partitions(ChartPeriod range) {
      final b = bucketsOf(range, today);
      expect(b.first.from, range.from);
      expect(b.last.to, range.to);
      for (var i = 1; i < b.length; i++) {
        expect(b[i].from, b[i - 1].to.plusDays(1));
      }
    }

    test('days, weeks and months partition the range exactly', () {
      partitions(p(d(2026, 10, 25), d(2026, 11, 24)));
      partitions(p(d(2026, 6, 1), d(2026, 11, 10)));
      partitions(p(d(2025, 12, 20), d(2026, 12, 31)));
      partitions(p(d(2024, 1, 31), d(2025, 12, 31)));
    });

    test('counts: 31 days, 26 weeks, 24 months', () {
      expect(
        bucketsOf(p(d(2026, 10, 25), d(2026, 11, 24)), today),
        hasLength(31),
      );
      expect(bucketsOf(p(d(2026, 1, 1), d(2026, 6, 30)), today), hasLength(26));
      final months = bucketsOf(p(d(2025, 1, 1), d(2026, 12, 31)), today);
      expect(months, hasLength(24));
      expect(months[1], p(d(2025, 2, 1), d(2025, 2, 28)));
    });

    test('months clip at the range edges and cover leap February', () {
      final b = bucketsOf(p(d(2023, 12, 15), d(2024, 7, 10)), today);
      expect(b.first, p(d(2023, 12, 15), d(2023, 12, 31)));
      expect(b[2], p(d(2024, 2, 1), d(2024, 2, 29)));
      expect(b.last, p(d(2024, 7, 1), d(2024, 7, 10)));
    });

    test('buckets after today are dropped', () {
      final b = bucketsOf(p(d(2026, 10, 25), d(2026, 11, 24)), d(2026, 11, 10));
      expect(b, hasLength(17));
      expect(b.last, p(d(2026, 11, 10), d(2026, 11, 10)));
    });

    test('net worth range widens to 12 months ending at the period end', () {
      expect(
        netWorthRange(p(d(2026, 10, 25), d(2026, 11, 24))),
        p(d(2025, 12, 1), d(2026, 11, 24)),
      );
      final two = p(d(2024, 11, 1), d(2026, 11, 10));
      expect(netWorthRange(two), two);
    });
  });

  group('six cycles (F1)', () {
    test('resolves to six cycles ending at the current one; steps by six', () {
      const s = ChartPeriodSelection(ChartPreset.last6Cycles);
      final today = d(2026, 11, 10);
      expect(res(s, today), p(d(2026, 5, 25), d(2026, 11, 24)));
      expect(res(s.stepped(1), today), p(d(2025, 11, 25), d(2026, 5, 24)));
      expect(s.canStepForward(today, p25), isFalse);
      expect(s.stepped(1).canStepForward(today, p25), isTrue);
    });

    test(
      'cash flow buckets: one per cycle, six, ending at the chosen cycle',
      () {
        final today = d(2026, 11, 10);
        for (final sel in const [
          ChartPeriodSelection.thisCycle,
          ChartPeriodSelection(ChartPreset.last6Cycles),
        ]) {
          final r = sel.resolveAll(today, p25);
          final b = cashFlowBuckets(r, today, p25);
          expect(b, hasLength(6), reason: sel.encode());
          expect(b.last, p(d(2026, 10, 25), d(2026, 11, 24)));
          expect(b.first.from, d(2026, 5, 25));
          for (var i = 1; i < b.length; i++) {
            expect(b[i].from, b[i - 1].to.plusDays(1));
          }
          expect(r.bucketKind, ChartBucketKind.cycle);
        }
        // A stepped cycle ends the trend at that cycle.
        final back = const ChartPeriodSelection(ChartPreset.lastCycle)
            .resolveAll(today, p25);
        expect(
          cashFlowBuckets(back, today, p25).last,
          p(d(2026, 9, 25), d(2026, 10, 24)),
        );
        // Other kinds use day/week/month buckets.
        final month = const ChartPeriodSelection(ChartPreset.thisMonth)
            .resolveAll(today, p25);
        expect(cashFlowBuckets(month, today, p25), hasLength(10));
      },
    );

    test('codec round trip', () {
      const s = ChartPeriodSelection(ChartPreset.last6Cycles, offset: 2);
      expect(ChartPeriodSelection.tryDecode(s.encode()), s);
    });
  });

  group('payday limits and custom clamp (F4, F6)', () {
    test(
      'payday above 28 does not exist: eras refuse it, resolve falls to 1',
      () {
        for (final day in [29, 30, 31]) {
          expect(() => PaydayEra(null, day), throwsArgumentError);
          expect(() => PaydaySchedule.single(day), throwsArgumentError);
          final s = PaydaySchedule.resolve(
            erasJson: null,
            paydayDay: day,
            today: d(2026, 2, 28),
          );
          expect(
            res(ChartPeriodSelection.thisCycle, d(2026, 2, 28), s),
            p(d(2026, 2, 1), d(2026, 2, 28)),
          );
        }
      },
    );

    test('payday 28 in 28-, 29- and 30-day months keeps cycles contiguous', () {
      final s = PaydaySchedule.single(28);
      for (final today in [
        d(2026, 2, 27),
        d(2024, 2, 29),
        d(2026, 4, 30),
        d(2026, 3, 1),
      ]) {
        final c = res(ChartPeriodSelection.thisCycle, today, s);
        final next = res(
          const ChartPeriodSelection(ChartPreset.thisCycle, offset: -1),
          today,
          s,
        );
        expect(next.from, c.to.plusDays(1));
        expect(c.contains(today), isTrue);
      }
    });

    test('a custom range stepped forward never ends after today', () {
      final today = d(2026, 11, 10);
      final s = ChartPeriodSelection.custom(d(2026, 10, 1), d(2026, 10, 31));
      final f = s.stepped(-1); // Nov 1 .. Nov 30
      expect(res(f, today), p(d(2026, 11, 1), today));
      final r = f.resolveAll(today, p25);
      expect(r.canStepForward, isFalse);
      // Compared with the same elapsed days of the range before.
      expect(r.previous.lengthDays, 10);
    });
  });
}
