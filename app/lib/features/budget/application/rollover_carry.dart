// FU-255: the one place that computes rollover carries (FR-BUD-05). The
// budget screen and the alert runner both call it, so an alert fires at the
// same effective limit (limit + carry) the screen shows. Per currency,
// integer minor units; a carry is the unused part of the previous cycle's
// limit, never negative. Annual budgets do not roll over. Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../data/cycle_repository.dart';
import '../domain/budget_progress.dart';

/// Carry into [cycle] per budget id, for the rollover, non-annual [specs].
/// Budgets that do not roll over have no entry.
Future<Map<String, Money>> rolloverCarries({
  required CycleRepository cycles,
  required PaydaySchedule schedule,
  required Cycle cycle,
  required Iterable<BudgetSpec> specs,
}) async {
  final rolling = [
    for (final s in specs)
      if (s.rollover && !s.annual) s,
  ];
  if (rolling.isEmpty) return const {};
  final prev = schedule.cycleOn(cycle.start.plusDays(-1));
  final prevTotals = await cycles.totals(prev);
  // A budget made after the previous cycle began did not exist for all of it,
  // so nothing was left unused (FR-BUD-05). The cut is the local start of the
  // previous cycle's first day in the cycle schedule's zone (FU-256), not UTC
  // midnight. The carry uses the current limit if it has changed.
  final wallMidnight = DateTime.utc(
    prev.start.year,
    prev.start.month,
    prev.start.day,
  );
  final prevStartMs =
      wallMidnight.millisecondsSinceEpoch -
      cycles.zone.offsetAtWallClock(wallMidnight) *
          Duration.millisecondsPerMinute;
  return {
    for (final s in rolling)
      s.id: s.createdAtMs > prevStartMs
          ? Money(s.limit.currency, 0)
          : rolloverCarry(s, prevTotals),
  };
}

/// The carry that belongs to the cycle budget basis of [currency]: the
/// overall budget's, else the sum of the category budgets' (A-16).
Money basisCarry(
  Currency currency,
  Iterable<BudgetSpec> specs,
  Map<String, Money> carries,
) {
  final mine = [
    for (final s in specs)
      if (!s.annual && s.limit.currency == currency) s,
  ];
  final overall = mine.where((s) => s.categoryId == null);
  final used = overall.isNotEmpty
      ? overall
      : mine.where((s) => s.categoryId != null);
  var sum = Money(currency, 0);
  for (final s in used) {
    final c = carries[s.id];
    if (c != null) sum = sum + c;
  }
  return sum;
}
