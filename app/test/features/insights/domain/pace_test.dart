// T-209 (AC 2): the pace maths, integer minor units.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/pace.dart';

void main() {
  test('cumulative per day, up to the elapsed days only', () {
    final p = computePace(
      dailyThis: [100, 0, 250, 50, 999],
      dailyPrev: const [],
      periodDays: 10,
      elapsedDays: 4,
      closed: false,
    );
    expect(p.cumulative, [100, 100, 350, 400]);
    expect(p.spent, 400);
    expect(p.elapsedDays, 4);
  });

  test('projection is spent / elapsed * period days, half away from zero', () {
    // 400 / 4 * 10 = 1000
    expect(
      computePace(
        dailyThis: [100, 0, 250, 50],
        dailyPrev: const [],
        periodDays: 10,
        elapsedDays: 4,
        closed: false,
      ).projectedMinor,
      1000,
    );
    // 10 * 31 / 3 = 103.33 -> 103; 11 * 31 / 3 = 113.67 -> 114
    int proj(int spent) => computePace(
      dailyThis: [spent, 0, 0],
      dailyPrev: const [],
      periodDays: 31,
      elapsedDays: 3,
      closed: false,
    ).projectedMinor!;
    expect(proj(10), 103);
    expect(proj(11), 114);
    // exactly .5 rounds up: 5 * 3 / 6 = 2.5 -> 3
    expect(
      computePace(
        dailyThis: [5, 0, 0, 0, 0, 0],
        dailyPrev: const [],
        periodDays: 3 * 2,
        elapsedDays: 6,
        closed: false,
      ).projectedMinor,
      5,
    );
    expect(
      computePace(
        dailyThis: [5, 0, 0],
        dailyPrev: const [],
        periodDays: 5,
        elapsedDays: 3,
        closed: false,
      ).projectedMinor,
      8, // 25 / 3 = 8.33
    );
    expect(
      computePace(
        dailyThis: [3, 0, 0],
        dailyPrev: const [],
        periodDays: 5,
        elapsedDays: 3,
        closed: false,
      ).projectedMinor,
      5, // 15 / 3 = 5 exactly
    );
    expect(
      computePace(
        dailyThis: [1, 0, 0],
        dailyPrev: const [],
        periodDays: 6,
        elapsedDays: 4,
        closed: false,
      ).projectedMinor,
      2, // 1 * 6 / 4 = 1.5 -> 2
    );
  });

  test('no projection before 3 days or when the period is closed', () {
    expect(
      computePace(
        dailyThis: [100, 100],
        dailyPrev: const [],
        periodDays: 30,
        elapsedDays: 2,
        closed: false,
      ).projectedMinor,
      isNull,
    );
    final closed = computePace(
      dailyThis: List.filled(30, 10),
      dailyPrev: const [],
      periodDays: 30,
      elapsedDays: 5,
      closed: true,
    );
    expect(closed.projectedMinor, isNull);
    // A closed period shows its whole line whatever "elapsed" says.
    expect(closed.cumulative.length, 30);
    expect(closed.spent, 300);
  });

  test('the previous period is compared at the same day, clamped', () {
    final p = computePace(
      dailyThis: [10, 10, 10, 10, 10, 10],
      dailyPrev: [5, 5, 5, 5], // a shorter previous period (4 days)
      periodDays: 10,
      elapsedDays: 6,
      closed: false,
    );
    expect(p.previousAt(2), 10);
    expect(p.previousAt(4), 20);
    expect(p.previousAt(6), 20, reason: 'clamped to its last day');
    expect(p.previousAt(31), 20);
    expect(p.comparisonBase, 20);
    expect(p.deltaMinor, 60 - 20);
  });

  test('a closed period compares totals', () {
    final p = computePace(
      dailyThis: [10, 10, 10, 10],
      dailyPrev: [20, 20, 20, 20],
      periodDays: 4,
      elapsedDays: 4,
      closed: true,
    );
    expect(p.comparisonBase, 80);
    expect(p.deltaMinor, -40);
  });

  test('budget line only when a budget exists', () {
    final none = computePace(
      dailyThis: [1, 1, 1],
      dailyPrev: const [],
      periodDays: 10,
      elapsedDays: 3,
      closed: false,
    );
    expect(none.budgetMinor, isNull);
    expect(none.leftInBudgetMinor, isNull);
    expect(none.overBudget, isNull);
    final b = computePace(
      dailyThis: [100, 100, 100],
      dailyPrev: const [],
      periodDays: 10,
      elapsedDays: 3,
      closed: false,
      budgetMinor: 2000,
    );
    expect(b.leftInBudgetMinor, 1700);
    expect(b.projectedMinor, 1000);
    expect(b.overBudget, isFalse);
    final over = computePace(
      dailyThis: [100, 100, 100],
      dailyPrev: const [],
      periodDays: 10,
      elapsedDays: 3,
      closed: false,
      budgetMinor: 900,
    );
    expect(over.overBudget, isTrue);
  });

  test('thin data: under 3 days, or no previous spending', () {
    PaceData make(int elapsed, List<int> prev) => computePace(
      dailyThis: [10, 10, 10, 10],
      dailyPrev: prev,
      periodDays: 10,
      elapsedDays: elapsed,
      closed: false,
    );
    expect(make(2, [5, 5, 5]).thin, isTrue);
    expect(make(4, const []).thin, isTrue);
    expect(make(4, [0, 0, 0]).thin, isTrue);
    expect(make(4, [5, 5, 5]).thin, isFalse);
    expect(make(2, [5, 5, 5]).comparisonBase, isNull);
    expect(make(2, [5, 5, 5]).deltaMinor, isNull);
  });

  test('zero transactions: a flat line at zero, no crash', () {
    final p = computePace(
      dailyThis: const [],
      dailyPrev: const [],
      periodDays: 30,
      elapsedDays: 10,
      closed: false,
    );
    expect(p.spent, 0);
    expect(p.projectedMinor, 0);
    expect(p.thin, isTrue);
  });

  test('elapsed days are clamped to the period', () {
    final p = computePace(
      dailyThis: List.filled(5, 1),
      dailyPrev: const [],
      periodDays: 5,
      elapsedDays: 99,
      closed: false,
    );
    expect(p.elapsedDays, 5);
    final q = computePace(
      dailyThis: List.filled(5, 1),
      dailyPrev: const [],
      periodDays: 5,
      elapsedDays: -3,
      closed: false,
    );
    expect(q.elapsedDays, 1);
  });

  test('day ticks: first, round days, last', () {
    expect(paceDayTicks(31), [1, 10, 20, 31]);
    expect(paceDayTicks(30), [1, 10, 20, 30]);
    expect(paceDayTicks(28), [1, 10, 20, 28]);
    expect(paceDayTicks(1), [1]);
    expect(paceDayTicks(7), [1, 7]);
    final year = paceDayTicks(365);
    expect(year.first, 1);
    expect(year.last, 365);
    expect(year.length, lessThanOrEqualTo(6));
  });
}
