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
      final idx = today.year * 12 + (today.month - 1) + _clamp(p.offset);
      return ChartPeriod.month(idx ~/ 12, idx % 12 + 1);
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
      final y = p.year ?? (m <= today.month ? today.year : today.year - 1);
      return ChartPeriod.month(y < 1 ? 1 : (y > 9999 ? 9999 : y), m);
    case AskPeriodKind.allTime:
      final f = firstDay != null && firstDay <= today ? firstDay : today;
      return ChartPeriod(f, today);
  }
}
