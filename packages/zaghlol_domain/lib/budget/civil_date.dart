/// A calendar date without time or zone (T-051). Backed by an epoch-day
/// integer (days since 1970-01-01), so all arithmetic is integer and a 23 or
/// 25 hour day (Cairo DST) cannot shift a day count. No `DateTime` is used.
final class CivilDate implements Comparable<CivilDate> {
  const CivilDate._(this.epochDay);

  /// The date [epochDay] days after 1970-01-01 (negative: before).
  const CivilDate.fromEpochDay(this.epochDay);

  /// Validated year/month/day. Throws [ArgumentError] for an impossible date
  /// or a year outside 1..9999.
  factory CivilDate(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      throw ArgumentError('invalid civil date');
    }
    if (day > daysInMonth(year, month)) {
      throw ArgumentError('invalid civil date');
    }
    return CivilDate._(_daysFromCivil(year, month, day));
  }

  /// The local civil date of the UTC instant [utcMs] in a zone whose offset
  /// is [offsetMin] minutes east of UTC. Floor division: 22:00Z with +180 is
  /// 01:00 of the next day.
  factory CivilDate.fromLocalMs(int utcMs, int offsetMin) {
    final local = utcMs + offsetMin * 60000;
    final rem = local % _msPerDay; // Dart: always >= 0 for a positive divisor
    return CivilDate._((local - rem) ~/ _msPerDay);
  }

  /// Parses `YYYY-MM-DD` (ASCII). Null for anything else.
  static CivilDate? tryParse(String text) {
    final m = _iso.firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (y < 1 || mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) {
      return null;
    }
    return CivilDate._(_daysFromCivil(y, mo, d));
  }

  static final RegExp _iso = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  static const int _msPerDay = 86400000;

  /// Days since 1970-01-01.
  final int epochDay;

  int get year => _civil.$1;
  int get month => _civil.$2;
  int get day => _civil.$3;

  (int, int, int) get _civil => _civilFromDays(epochDay);

  CivilDate plusDays(int days) => CivilDate._(epochDay + days);

  /// `this - other` in days.
  int difference(CivilDate other) => epochDay - other.epochDay;

  /// `YYYY-MM-DD`.
  String toIso() {
    final (y, m, d) = _civil;
    return '${y.toString().padLeft(4, '0')}-'
        '${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  static bool isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  static int daysInMonth(int y, int m) => switch (m) {
    2 => isLeapYear(y) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  @override
  int compareTo(CivilDate other) => epochDay.compareTo(other.epochDay);

  bool operator <(CivilDate o) => epochDay < o.epochDay;
  bool operator <=(CivilDate o) => epochDay <= o.epochDay;
  bool operator >(CivilDate o) => epochDay > o.epochDay;
  bool operator >=(CivilDate o) => epochDay >= o.epochDay;

  @override
  bool operator ==(Object other) =>
      other is CivilDate && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay.hashCode;

  @override
  String toString() => toIso();

  // Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian).
  static int _daysFromCivil(int y, int m, int d) {
    final yy = m <= 2 ? y - 1 : y;
    final era = (yy >= 0 ? yy : yy - 399) ~/ 400;
    final yoe = yy - era * 400;
    final doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) ~/ 5 + d - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  static (int, int, int) _civilFromDays(int z0) {
    final z = z0 + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final doe = z - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final y = yoe + era * 400;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final d = doy - (153 * mp + 2) ~/ 5 + 1;
    final m = mp < 10 ? mp + 3 : mp - 9;
    return (m <= 2 ? y + 1 : y, m, d);
  }
}
