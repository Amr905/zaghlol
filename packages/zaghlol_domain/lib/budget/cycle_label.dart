// T-247 (D-82): the calendar month a payday cycle is named after. A cycle
// that starts on day 21 or later is the next month's ("payday 24 Nov" opens
// the December cycle); one that starts on day 1..20 is named by its own
// month. Pure; every screen that shows a cycle as a month goes through here.

import 'civil_date.dart';

/// The first day of a cycle that belongs to the next month (D-82).
const int cycleNextMonthFromDay = 21;

/// A named calendar month.
typedef CycleMonth = ({int year, int month});

/// The month a cycle that starts on [cycleStart] is named after.
CycleMonth cycleLabelMonth(CivilDate cycleStart) {
  if (cycleStart.day < cycleNextMonthFromDay) {
    return (year: cycleStart.year, month: cycleStart.month);
  }
  return cycleStart.month == 12
      ? (year: cycleStart.year + 1, month: 1)
      : (year: cycleStart.year, month: cycleStart.month + 1);
}
