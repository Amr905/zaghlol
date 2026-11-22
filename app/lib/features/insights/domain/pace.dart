// T-209 (CHARTS-V2): the spending pace of one period against the period
// before it. Pure Dart, integer minor units of ONE currency, no double.
// Nothing here logs.

import 'chart_models.dart' show ChartThresholds;
import 'chart_rules.dart' show mulDivRound;

/// Cumulative spend per day for a period and its comparison.
final class PaceData {
  PaceData({
    required this.periodDays,
    required this.elapsedDays,
    required this.closed,
    required List<int> cumulative,
    required List<int> previousCumulative,
    required this.budgetMinor,
    required this.projectedMinor,
  }) : cumulative = List.unmodifiable(cumulative),
       previousCumulative = List.unmodifiable(previousCumulative);

  /// Days of the period (the x axis runs 1..periodDays).
  final int periodDays;

  /// Days that have started, 1..[periodDays]; a closed period is complete.
  final int elapsedDays;

  /// The period ended before today: the whole line, no projection.
  final bool closed;

  /// Cumulative spend at the end of day 1..[elapsedDays].
  final List<int> cumulative;

  /// The whole previous period, cumulative per day; empty when it is unknown.
  final List<int> previousCumulative;

  /// The budget basis, or null when there is no budget.
  final int? budgetMinor;

  /// Straight-line projection to the end of the period; null when closed or
  /// before [ChartThresholds.projectionMinDays] days.
  final int? projectedMinor;

  int get spent => cumulative.isEmpty ? 0 : cumulative.last;

  int get previousTotal =>
      previousCumulative.isEmpty ? 0 : previousCumulative.last;

  /// The previous period's cumulative spend at [day] (1-based). A shorter
  /// previous period is clamped to its last day. Null without a previous.
  int? previousAt(int day) {
    if (previousCumulative.isEmpty) return null;
    final i = day.clamp(1, previousCumulative.length) - 1;
    return previousCumulative[i];
  }

  /// Fewer than three days, or nothing to compare with: the hero shows only
  /// the number and a "not enough data yet" line.
  bool get thin =>
      elapsedDays < ChartThresholds.projectionMinDays || previousTotal <= 0;

  /// What the previous period had spent by this day, or, for a closed
  /// period, in total.
  int? get comparisonBase =>
      thin ? null : (closed ? previousTotal : previousAt(elapsedDays));

  /// This period minus the comparison; null when [thin].
  int? get deltaMinor {
    final base = comparisonBase;
    return base == null ? null : spent - base;
  }

  /// The budget left at the pace so far; null without a budget.
  int? get leftInBudgetMinor =>
      budgetMinor == null ? null : budgetMinor! - spent;

  /// The projection or, for a closed period, the total is over the budget.
  bool? get overBudget {
    if (budgetMinor == null) return null;
    final end = projectedMinor ?? (closed ? spent : null);
    return end == null ? null : end > budgetMinor!;
  }
}

List<int> _cumulate(List<int> daily, int days) {
  final out = <int>[];
  var run = 0;
  for (var i = 0; i < days; i++) {
    run += i < daily.length ? daily[i] : 0;
    out.add(run);
  }
  return out;
}

/// The pace of a period. [dailyThis] and [dailyPrev] hold the spend of each
/// day in minor units, index 0 being the first day of the period; days
/// missing from a list count as zero. [elapsedDays] is clamped to
/// 1..[periodDays]; a [closed] period uses all of its days.
PaceData computePace({
  required List<int> dailyThis,
  required List<int> dailyPrev,
  required int periodDays,
  required int elapsedDays,
  required bool closed,
  int? budgetMinor,
}) {
  if (periodDays < 1) throw ArgumentError('a period has at least one day');
  final days = closed ? periodDays : elapsedDays.clamp(1, periodDays);
  final cumulative = _cumulate(dailyThis, days);
  final projected = !closed && days >= ChartThresholds.projectionMinDays
      ? mulDivRound(cumulative.last, periodDays, days)
      : null;
  return PaceData(
    periodDays: periodDays,
    elapsedDays: days,
    closed: closed,
    cumulative: cumulative,
    previousCumulative: dailyPrev.isEmpty
        ? const []
        : _cumulate(dailyPrev, dailyPrev.length),
    budgetMinor: budgetMinor,
    projectedMinor: projected,
  );
}

/// The days (1-based) labelled on the x axis: the first, a few round
/// numbers (every 10 days, or every 100 for a long period) and the last.
/// A round day too close to the last one is dropped.
List<int> paceDayTicks(int periodDays) {
  if (periodDays <= 1) return const [1];
  final step = periodDays <= 40 ? 10 : ((periodDays + 3) ~/ 4 + 9) ~/ 10 * 10;
  final ticks = <int>[1];
  for (var d = step; d < periodDays - step ~/ 3; d += step) {
    ticks.add(d);
  }
  ticks.add(periodDays);
  return ticks;
}
