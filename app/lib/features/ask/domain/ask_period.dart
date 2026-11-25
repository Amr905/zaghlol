// T-110: turns a spoken period into a concrete local-date range. Pure; the
// week starts on Saturday (Egypt), the cycle comes from the payday schedule.
// Offsets are clamped so no date leaves the supported years.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../insights/domain/chart_models.dart';
import '../../insights/domain/chart_rules.dart';

const int _maxBack = 120;
const int _maxFwd = 24;

int _clamp(int v) => v < -_maxBack ? -_maxBack : (v > _maxFwd ? _maxFwd : v);

/// The range of [p] on [today]. [firstDay] is the user's first transaction
/// day, used by "all time" (today when there is no data).
ChartPeriod resolveAskPeriod(
  AskPeriod p,
  CivilDate today,
  PaydaySchedule schedule, {
  CivilDate? firstDay,
}) {
  switch (p.kind) {
    case AskPeriodKind.day:
      final d = today.plusDays(_clamp(p.offset));
      return ChartPeriod(d, d);
    case AskPeriodKind.week:
      // Saturday = ISO weekday 6.
      final back = (isoWeekday(today.epochDay) - 6 + 7) % 7;
      final start = today.plusDays(-back + 7 * _clamp(p.offset));
      return ChartPeriod(start, start.plusDays(6));
    case AskPeriodKind.month:
      // D-82 / T-247: the cycle is the reporting unit, named by its label
      // month ("this month" is the cycle that holds today). With payday 1 a
      // cycle is the calendar month, so nothing changes there.
      var c = schedule.cycleOn(today);
      final o = _clamp(p.offset);
      for (var i = 0; i < o.abs(); i++) {
        c = o < 0 ? schedule.before(c) : schedule.after(c);
      }
      return ChartPeriod.cycle(c);
    case AskPeriodKind.year:
      final y = today.year + _clamp(p.offset);
      return ChartPeriod(CivilDate(y, 1, 1), CivilDate(y, 12, 31));
    case AskPeriodKind.cycle:
      var c = schedule.cycleOn(today);
      final o = _clamp(p.offset);
      for (var i = 0; i < o.abs(); i++) {
        c = o < 0 ? schedule.before(c) : schedule.after(c);
      }
      return ChartPeriod.cycle(c);
    case AskPeriodKind.lastDays:
      final n = p.count < 1 ? 1 : (p.count > 366 ? 366 : p.count);
      return ChartPeriod(today.plusDays(1 - n), today);
    case AskPeriodKind.monthOfYear:
      final m = p.month < 1 || p.month > 12 ? today.month : p.month;
      if (p.year == null) {
        final named = _nearestCycleNamed(schedule, today, m);
        if (named != null) return named;
      }
      final y = p.year ?? (m <= today.month ? today.year : today.year - 1);
      final year = y < 1 ? 1 : (y > 9999 ? 9999 : y);
      return _cycleNamed(schedule, year, m) ?? ChartPeriod.month(year, m);
    case AskPeriodKind.allTime:
      final f = firstDay != null && firstDay <= today ? firstDay : today;
      return ChartPeriod(f, today);
  }
}

/// The cycle named after [month] of [year] (D-82), or null when none of the
/// cycles around the middle of that month is (an odd payday history).
ChartPeriod? _cycleNamed(PaydaySchedule schedule, int year, int month) {
  final mid = schedule.cycleOn(CivilDate(year, month, 15));
  for (final c in [mid, schedule.before(mid), schedule.after(mid)]) {
    final m = cycleLabelMonth(c.start);
    if (m.year == year && m.month == month) return ChartPeriod.cycle(c);
  }
  return null;
}

/// FU-307: the nearest cycle named [month] that is not in the future (the
/// current cycle counts), found among the cycles around today.
ChartPeriod? _nearestCycleNamed(
  PaydaySchedule schedule,
  CivilDate today,
  int month,
) {
  var c = schedule.cycleOn(today);
  for (var i = 0; i < 14; i++) {
    if (cycleLabelMonth(c.start).month == month) return ChartPeriod.cycle(c);
    c = schedule.before(c);
  }
  return null;
}
