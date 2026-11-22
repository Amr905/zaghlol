// T-211 (CHARTS-V2): pure models of the Trends tab: the "In and out" bars and
// the "Day by day" heatmap. Integer minor units of ONE currency, no double.
// Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;

import 'chart_models.dart'
    show CashFlowPoint, ChartPeriod, ChartThresholds, DayHourPattern;
import 'chart_rules.dart' show mulDivRound;

// ------------------------------------------------------------- in and out

final class InOutBar {
  const InOutBar({
    required this.from,
    required this.to,
    required this.incomeMinor,
    required this.spendMinor,
    required this.hasData,
    required this.projected,
  });

  final CivilDate from;
  final CivilDate to;
  final int incomeMinor;

  /// For a [projected] bar: the spend projected to the end of the bucket.
  final int spendMinor;

  /// False for a month with no income and no spending: an empty slot.
  final bool hasData;
  final bool projected;
}

/// The bars for [points] (oldest first, one currency). The open bucket is
/// projected like "saved each month" (T-209, `savedMonths`).
List<InOutBar> inOutBars(List<CashFlowPoint> points, CivilDate today) {
  final out = <InOutBar>[];
  for (final p in points) {
    final from = p.period.from;
    final to = p.period.to;
    var spend = p.spend.minor;
    var projected = false;
    if (to >= today && from <= today) {
      final elapsed = today.difference(from) + 1;
      final length = to.difference(from) + 1;
      if (elapsed >= ChartThresholds.projectionMinDays && elapsed < length) {
        spend = mulDivRound(spend, length, elapsed);
        projected = true;
      }
    }
    out.add(
      InOutBar(
        from: from,
        to: to,
        incomeMinor: p.income.minor,
        spendMinor: spend,
        hasData: p.income.minor != 0 || p.spend.minor != 0,
        projected: projected,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------- heatmap

/// Number of colour steps, the lightest being a zero day.
const int kHeatLevels = 5;

/// The three cut points between levels 1..4 of the NON-zero days: the 25th,
/// 50th and 75th percentile by nearest rank. Empty when there is no
/// non-zero day.
List<int> heatThresholds(List<int> daily) {
  final v = [
    for (final d in daily)
      if (d > 0) d,
  ]..sort();
  if (v.isEmpty) return const [];
  final n = v.length;
  return [for (var k = 1; k <= 3; k++) v[((k * n + 3) ~/ 4) - 1]];
}

/// 0 for a day without spending, else 1..4: one more than the number of cut
/// points the value is above.
int heatLevel(int minor, List<int> thresholds) {
  if (minor <= 0) return 0;
  var level = 1;
  for (final t in thresholds) {
    if (minor > t) level++;
  }
  return level;
}

final class HeatDay {
  const HeatDay({
    required this.date,
    required this.minor,
    required this.level,
    required this.future,
    required this.isToday,
  });
  final CivilDate date;
  final int minor;
  final int level;

  /// After today: outlined, not filled.
  final bool future;
  final bool isToday;
}

final class HeatGrid {
  HeatGrid({required this.leading, required List<HeatDay> days})
    : days = List.unmodifiable(days);

  /// Empty cells before the first day (week rows start on Saturday).
  final int leading;
  final List<HeatDay> days;

  int get rows => (leading + days.length + 6) ~/ 7;
}

/// Position of [d] in a week that starts on Saturday: Sat 0 .. Fri 6.
int saturdayIndex(CivilDate d) =>
    (DateTime.utc(d.year, d.month, d.day).weekday + 1) % 7;

/// ISO weekday (1 Monday .. 7 Sunday) of [d].
int isoWeekday(CivilDate d) => DateTime.utc(d.year, d.month, d.day).weekday;

/// The grid of [period]: [daily] holds the net spend of each day, first day
/// first. Levels come from the non-zero days up to [today].
HeatGrid buildHeatGrid(ChartPeriod period, List<int> daily, CivilDate today) {
  final past = [
    for (var i = 0; i < period.lengthDays; i++)
      if (period.from.plusDays(i) <= today && i < daily.length) daily[i],
  ];
  final th = heatThresholds(past);
  final days = <HeatDay>[];
  for (var i = 0; i < period.lengthDays; i++) {
    final d = period.from.plusDays(i);
    final future = d > today;
    final v = i < daily.length ? daily[i] : 0;
    days.add(
      HeatDay(
        date: d,
        minor: future ? 0 : v,
        level: future ? 0 : heatLevel(v, th),
        future: future,
        isToday: d == today,
      ),
    );
  }
  return HeatGrid(leading: saturdayIndex(period.from), days: days);
}

/// Days of data needed before the priciest weekday is named (two weeks).
const int kHeatCaptionMinDays = 14;

/// The ISO weekday with the most spending, or null when the period has
/// fewer than [kHeatCaptionMinDays] elapsed days or nothing was spent. A tie
/// goes to the earlier day of the Saturday-first week.
int? priciestWeekday(DayHourPattern p, {required int elapsedDays}) {
  if (elapsedDays < kHeatCaptionMinDays) return null;
  int? best;
  var bestMinor = 0;
  for (final d in const [6, 7, 1, 2, 3, 4, 5]) {
    final m = p.byWeekday[d]?.spend.minor ?? 0;
    if (m > bestMinor) {
      best = d;
      bestMinor = m;
    }
  }
  return best;
}
