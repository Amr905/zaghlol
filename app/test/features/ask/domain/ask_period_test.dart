// T-110: spoken period -> local-date range. Today is Tue 2026-11-10, payday
// 25 (cycle 25 Oct .. 24 Nov).

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ask/domain/ask_period.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);

void main() {
  final today = d(2026, 11, 10);
  final schedule = PaydaySchedule.single(25);
  String r(AskPeriod p, {CivilDate? first}) {
    final c = resolveAskPeriod(p, today, schedule, firstDay: first);
    return '${c.from.toIso()}..${c.to.toIso()}';
  }

  test('day, week (Saturday start), month, year', () {
    expect(r(const AskPeriod(AskPeriodKind.day)), '2026-11-10..2026-11-10');
    expect(
      r(const AskPeriod(AskPeriodKind.day, offset: -1)),
      '2026-11-09..2026-11-09',
    );
    expect(r(const AskPeriod(AskPeriodKind.week)), '2026-11-07..2026-11-13');
    expect(
      r(const AskPeriod(AskPeriodKind.week, offset: -1)),
      '2026-10-31..2026-11-06',
    );
    // D-82 (T-247): "month" is the payday cycle that holds today.
    expect(r(const AskPeriod(AskPeriodKind.month)), '2026-10-25..2026-11-24');
    expect(
      r(const AskPeriod(AskPeriodKind.month, offset: -1)),
      '2026-09-25..2026-10-24',
    );
    expect(
      r(const AskPeriod(AskPeriodKind.month, offset: -11)),
      '2025-11-25..2025-12-24',
    );
    expect(
      r(const AskPeriod(AskPeriodKind.year, offset: -1)),
      '2025-01-01..2025-12-31',
    );
  });

  test('a Saturday starts its own week', () {
    final sat = resolveAskPeriod(
      const AskPeriod(AskPeriodKind.week),
      d(2026, 11, 7),
      schedule,
    );
    expect(sat.from, d(2026, 11, 7));
  });

  test('cycle, last days, month of year, all time', () {
    expect(r(const AskPeriod(AskPeriodKind.cycle)), '2026-10-25..2026-11-24');
    expect(
      r(const AskPeriod(AskPeriodKind.cycle, offset: -1)),
      '2026-09-25..2026-10-24',
    );
    expect(
      r(const AskPeriod(AskPeriodKind.lastDays, count: 30)),
      '2026-10-12..2026-11-10',
    );
    // A named month is the cycle named after it (payday 25: starts 25 Feb).
    expect(
      r(const AskPeriod(AskPeriodKind.monthOfYear, month: 3)),
      '2026-02-25..2026-03-24',
    );
    // A month still ahead this year means last year's.
    expect(
      r(const AskPeriod(AskPeriodKind.monthOfYear, month: 12)),
      '2025-11-25..2025-12-24',
    );
    expect(
      r(const AskPeriod(AskPeriodKind.monthOfYear, month: 2, year: 2024)),
      '2024-01-25..2024-02-24',
    );
    expect(
      r(const AskPeriod(AskPeriodKind.allTime), first: d(2026, 1, 5)),
      '2026-01-05..2026-11-10',
    );
    expect(r(const AskPeriod(AskPeriodKind.allTime)), '2026-11-10..2026-11-10');
  });

  test('hostile offsets and counts are clamped, never throw', () {
    expect(
      () => r(const AskPeriod(AskPeriodKind.month, offset: -999999)),
      returnsNormally,
    );
    expect(
      () => r(const AskPeriod(AskPeriodKind.year, offset: 999999)),
      returnsNormally,
    );
    expect(
      () => r(const AskPeriod(AskPeriodKind.cycle, offset: -999999)),
      returnsNormally,
    );
    final big = resolveAskPeriod(
      const AskPeriod(AskPeriodKind.lastDays, count: 1 << 40),
      today,
      schedule,
    );
    expect(big.lengthDays, 366);
    final bad = resolveAskPeriod(
      const AskPeriod(AskPeriodKind.monthOfYear, month: 99, year: -5),
      today,
      schedule,
    );
    expect(bad.from.year, 1);
  });

  group('cycle naming (D-82)', () {
    // Payday 24, today 25 Nov: the cycle 24 Nov .. 23 Dec is "December".
    final p24 = PaydaySchedule.single(24);
    String at24(AskPeriod p, CivilDate today) {
      final c = resolveAskPeriod(p, today, p24);
      return '${c.from.toIso()}..${c.to.toIso()}';
    }

    test('"this month" after payday 24 is the cycle named December', () {
      expect(
        at24(const AskPeriod(AskPeriodKind.month), d(2026, 11, 25)),
        '2026-11-24..2026-12-23',
      );
      expect(
        at24(const AskPeriod(AskPeriodKind.month, offset: -1), d(2026, 11, 25)),
        '2026-10-24..2026-11-23',
      );
    });

    test('before payday 24 "this month" is still the cycle named November', () {
      expect(
        at24(const AskPeriod(AskPeriodKind.month), d(2026, 11, 10)),
        '2026-10-24..2026-11-23',
      );
    });

    test('a named month is the cycle named after it, across the new year', () {
      expect(
        at24(
          const AskPeriod(AskPeriodKind.monthOfYear, month: 1, year: 2027),
          d(2027, 2, 1),
        ),
        '2026-12-24..2027-01-23',
      );
    });

    test('payday 1: a month is the calendar month, as before', () {
      final c = resolveAskPeriod(
        const AskPeriod(AskPeriodKind.month),
        d(2026, 11, 25),
        PaydaySchedule.single(1),
      );
      expect(c.key, '2026-11-01..2026-11-30');
    });
  });
}
