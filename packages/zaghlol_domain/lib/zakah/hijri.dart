// T-167: Hijri date for the Zakah ledger's `lot_start_hijri` (FR-ZAK-01).
//
// This is the TABULAR (arithmetic civil) Islamic calendar, which can differ
// from Umm al-Qura by one day. Hawl length is counted in days (BR-ZAK-02:
// 354), never from this date, so the difference can't change a due date; the
// Hijri date is for display and storage only. Bundling the Umm al-Qura table
// is listed under "For the scholar" in T-167.

import '../budget/civil_date.dart';

final class HijriDate {
  const HijriDate(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;

  /// `YYYY-MM-DD`, month 01..12, day 01..30 (the `zakah_ledger` CHECK).
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is HijriDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

// Rata Die of 1970-01-01 and of 1 Muharram 1 AH (civil epoch, 16 Jul 622 Jul.).
const int _rdUnixEpoch = 719163;
const int _rdIslamicEpoch = 227015;

int _fixed(int y, int m, int d) =>
    d +
    29 * (m - 1) +
    (6 * m - 1) ~/ 11 +
    (y - 1) * 354 +
    (3 + 11 * y) ~/ 30 +
    _rdIslamicEpoch -
    1;

/// Tabular Hijri date of [date]. Dates before 1 Muharram 1 AH are refused.
HijriDate hijriFromCivil(CivilDate date) {
  final rd = date.epochDay + _rdUnixEpoch;
  if (rd < _rdIslamicEpoch) {
    throw ArgumentError('date before the Hijri epoch');
  }
  final year = (30 * (rd - _rdIslamicEpoch) + 10646) ~/ 10631;
  final prior = rd - _fixed(year, 1, 1);
  final month = (11 * prior + 330) ~/ 325;
  final day = rd - _fixed(year, month, 1) + 1;
  return HijriDate(year, month, day);
}
