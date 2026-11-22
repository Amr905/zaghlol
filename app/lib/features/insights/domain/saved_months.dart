// T-209 (CHARTS-V2): "saved each month": income minus spending per bucket as
// diverging bars, the open bucket projected, and the average of the complete
// ones. Pure Dart, integer minor units of one currency, no double.

import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;

import 'chart_models.dart' show CashFlowPoint, ChartThresholds;
import 'chart_rules.dart' show mulDivRound;

final class SavedBar {
  const SavedBar({
    required this.from,
    required this.to,
    required this.netMinor,
    required this.projected,
  });

  /// The bucket's own dates (the label names the month of [to]).
  final CivilDate from;
  final CivilDate to;

  /// Income minus spend. For a [projected] bar the spend is projected to the
  /// end of the bucket.
  final int netMinor;
  final bool projected;
}

final class SavedMonths {
  SavedMonths({required List<SavedBar> bars, required this.averageMinor})
    : bars = List.unmodifiable(bars);

  final List<SavedBar> bars;

  /// Mean of the complete (not projected) bars, rounded half away from zero;
  /// null when there is none.
  final int? averageMinor;
}

/// The bars for [points] (oldest first, one currency). The bucket that
/// contains [today] and has not ended is the open one: its spend is
/// projected to its last day once [ChartThresholds.projectionMinDays] days
/// have passed, and it is not part of the average.
SavedMonths savedMonths(List<CashFlowPoint> points, CivilDate today) {
  final bars = <SavedBar>[];
  var sum = 0;
  var complete = 0;
  for (final p in points) {
    final from = p.period.from;
    final to = p.period.to;
    final open = to >= today && from <= today;
    var net = p.income.minor - p.spend.minor;
    var projected = false;
    if (open) {
      final elapsed = today.difference(from) + 1;
      final length = to.difference(from) + 1;
      if (elapsed >= ChartThresholds.projectionMinDays && elapsed < length) {
        net = p.income.minor - mulDivRound(p.spend.minor, length, elapsed);
        projected = true;
      }
    }
    if (!projected && !open) {
      sum += net;
      complete++;
    }
    bars.add(SavedBar(from: from, to: to, netMinor: net, projected: projected));
  }
  return SavedMonths(
    bars: bars,
    averageMinor: complete == 0 ? null : mulDivRound(sum, 1, complete),
  );
}
