// T-156: dates as they appear on Egyptian bank statements.
//
// Formats: 05/01/2026, 5-1-26, 05.01.2026, 2026-01-05, 05 Jan 2026,
// 5 January 2026, ٠٥/٠١/٢٠٢٦, 5 يناير 2026 (Egyptian and standard month
// spellings), each with an optional trailing time that is ignored. The day
// and month order of numeric dates is a flag from the template, not a guess;
// a date that is not a real calendar day is null.

import '../../normalize/text_normalizer.dart';

/// A calendar day, no time zone.
final class StatementDate {
  const StatementDate(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is StatementDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'StatementDate';
}

const Map<String, int> _monthNames = {
  'jan': 1, 'january': 1,
  'feb': 2, 'february': 2,
  'mar': 3, 'march': 3,
  'apr': 4, 'april': 4,
  'may': 5,
  'jun': 6, 'june': 6,
  'jul': 7, 'july': 7,
  'aug': 8, 'august': 8,
  'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10,
  'nov': 11, 'november': 11,
  'dec': 12, 'december': 12,
  // Arabic, folded with foldKey at lookup (ا for أ/إ, ه for ة, ي for ى).
  'يناير': 1, 'كانون الثاني': 1,
  'فبراير': 2, 'شباط': 2,
  'مارس': 3, 'اذار': 3,
  'ابريل': 4, 'نيسان': 4,
  'مايو': 5, 'ايار': 5,
  'يونيو': 6, 'يونيه': 6, 'يونيوه': 6, 'حزيران': 6,
  'يوليو': 7, 'يوليه': 7, 'تموز': 7,
  'اغسطس': 8, 'اب': 8,
  'سبتمبر': 9, 'ايلول': 9,
  'اكتوبر': 10, 'تشرين الاول': 10,
  'نوفمبر': 11, 'تشرين الثاني': 11,
  'ديسمبر': 12, 'كانون الاول': 12,
};

final Map<String, int> _months = {
  for (final e in _monthNames.entries) foldKey(e.key): e.value,
};

final RegExp _time = RegExp(r'[\s,T]+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?$');
final RegExp _numeric = RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$');
final RegExp _textual = RegExp(
  r'^(\d{1,2})[\s\-/.,]+([^\d\s\-/.,]+(?: [^\d\s\-/.,]+)?)[\s\-/.,]+(\d{2,4})$',
);

/// A day and month with no year (`10/02`, `Oct 10`); the year comes from the
/// statement (see [resolveStatementYears]).
final class PartialDate {
  const PartialDate(this.month, this.day);
  final int month;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is PartialDate && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);

  @override
  String toString() => 'PartialDate';
}

// Only `/` and `-`: `10.25` is an amount, not 25 October.
final RegExp _numericShort = RegExp(r'^(\d{1,2})[/\-](\d{1,2})$');
final RegExp _textShortDayFirst = RegExp(
  r'^(\d{1,2})[\s\-/.,]+([^\d\s\-/.,]+(?: [^\d\s\-/.,]+)?)$',
);
final RegExp _textShortMonthFirst = RegExp(
  r'^([^\d\s\-/.,]+(?: [^\d\s\-/.,]+)?)[\s\-/.,]+(\d{1,2})$',
);
final RegExp _textMonthFirstYear = RegExp(
  r'^([^\d\s\-/.,]+(?: [^\d\s\-/.,]+)?)[\s\-/.,]+(\d{1,2})[\s,]+(\d{4})$',
);

/// Parses a date with no year: `10/02` (month first unless [dayFirst]),
/// `10 Oct`, `Oct 10`. Null for anything else, including a full date.
PartialDate? parsePartialStatementDate(String text, {bool dayFirst = true}) {
  var t = foldKey(text);
  if (t.isEmpty || t.length > 20) return null;
  t = t.replaceFirst(_time, '').trim();
  PartialDate? make(int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return PartialDate(m, d);
  }

  final n = _numericShort.firstMatch(t);
  if (n != null) {
    final a = int.parse(n.group(1)!);
    final b = int.parse(n.group(2)!);
    return dayFirst ? make(b, a) : make(a, b);
  }
  final m1 = _textShortDayFirst.firstMatch(t);
  if (m1 != null) {
    final month = _months[m1.group(2)!.trim()];
    return month == null ? null : make(month, int.parse(m1.group(1)!));
  }
  final m2 = _textShortMonthFirst.firstMatch(t);
  if (m2 != null) {
    final month = _months[m2.group(1)!.trim()];
    return month == null ? null : make(month, int.parse(m2.group(2)!));
  }
  return null;
}

/// Day-first or month-first for numeric dates, from the cells themselves:
/// a first part above 12 means day first, a second part above 12 means
/// month first. Null when every date is ambiguous (the caller's default
/// stands) or the cells contradict each other.
bool? detectDayFirst(Iterable<String> cells) {
  var dayFirst = false;
  var monthFirst = false;
  for (final c in cells) {
    var t = foldKey(c);
    if (t.length > 20) continue;
    t = t.replaceFirst(_time, '').trim();
    final long = _numeric.firstMatch(t);
    final short = _numericShort.firstMatch(t);
    final String a;
    final String b;
    if (long != null) {
      if (long.group(1)!.length == 4) continue;
      a = long.group(1)!;
      b = long.group(2)!;
    } else if (short != null) {
      a = short.group(1)!;
      b = short.group(2)!;
    } else {
      continue;
    }
    if (int.parse(a) > 12) dayFirst = true;
    if (int.parse(b) > 12) monthFirst = true;
  }
  if (dayFirst == monthFirst) return null;
  return dayFirst;
}

/// Parses [text] as a date, or returns null. [dayFirst] decides `05/01/2026`
/// (5 January when true, 1 May when false); a four-digit first part is always
/// the year.
StatementDate? parseStatementDate(String text, {bool dayFirst = true}) {
  var t = foldKey(text);
  if (t.isEmpty || t.length > 40) return null;
  t = t.replaceFirst(_time, '').trim();
  final n = _numeric.firstMatch(t);
  if (n != null) {
    final a = n.group(1)!;
    final b = int.parse(n.group(2)!);
    final c = n.group(3)!;
    if (a.length == 4) {
      return _make(int.parse(a), b, int.parse(c));
    }
    if (c.length != 2 && c.length != 4) return null;
    final year = _year(c);
    final x = int.parse(a);
    return dayFirst ? _make(year, b, x) : _make(year, x, b);
  }
  final m = _textual.firstMatch(t);
  if (m != null) {
    final month = _months[m.group(2)!.trim()];
    if (month == null) return null;
    return _make(_year(m.group(3)!), month, int.parse(m.group(1)!));
  }
  final mf = _textMonthFirstYear.firstMatch(t);
  if (mf != null) {
    final month = _months[mf.group(1)!.trim()];
    if (month == null) return null;
    return _make(int.parse(mf.group(3)!), month, int.parse(mf.group(2)!));
  }
  return null;
}

/// Gives each year-less row a year. [dates] is one entry per row in the
/// order of the statement: a [StatementDate] (kept as is), a [PartialDate]
/// (resolved) or null (a bad date, stays null).
///
/// The statement is assumed to end no later than [anchor] (the latest full
/// date printed outside the table, or today). The row order is read from the
/// month sequence: a drop of six months or more (Dec to Jan) in a list that
/// goes forward, or a rise of that size in one that goes backward, is a year
/// change. The row that is latest in time gets the latest year whose date is
/// not after [anchor]; earlier rows step back one year at each rollover.
List<StatementDate?> resolveStatementYears(
  List<Object?> dates, {
  required StatementDate anchor,
}) {
  int monthOf(Object? d) => switch (d) {
    StatementDate(:final month) => month,
    PartialDate(:final month) => month,
    _ => 0,
  };
  final idx = [
    for (var i = 0; i < dates.length; i++)
      if (dates[i] != null) i,
  ];
  final out = List<StatementDate?>.filled(dates.length, null);
  if (idx.isEmpty) return out;
  var forward = 0;
  var backward = 0;
  for (var k = 1; k < idx.length; k++) {
    final d = monthOf(dates[idx[k]]) - monthOf(dates[idx[k - 1]]);
    if (d <= -6) forward++;
    if (d >= 6) backward++;
  }
  final chrono = backward > forward ? idx.reversed.toList() : idx;
  // Latest in time is the last of [chrono].
  int? year;
  int? lastMonth;
  for (var k = chrono.length - 1; k >= 0; k--) {
    final d = dates[chrono[k]];
    if (d is StatementDate) {
      out[chrono[k]] = d;
      year = d.year;
      lastMonth = d.month;
      continue;
    }
    final p = d as PartialDate;
    if (year == null) {
      final inAnchorYear =
          (p.month, p.day).compareTo2(anchor.month, anchor.day) <= 0;
      year = inAnchorYear ? anchor.year : anchor.year - 1;
    } else if (lastMonth != null && p.month - lastMonth >= 6) {
      year -= 1;
    }
    lastMonth = p.month;
    out[chrono[k]] = _make(year, p.month, p.day);
  }
  return out;
}

extension on (int, int) {
  int compareTo2(int month, int day) =>
      $1 != month ? $1.compareTo(month) : $2.compareTo(day);
}

int _year(String s) {
  final v = int.parse(s);
  return s.length == 2 ? 2000 + v : v;
}

StatementDate? _make(int y, int m, int d) {
  if (y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1) return null;
  final last = DateTime.utc(y, m + 1, 0).day;
  return d > last ? null : StatementDate(y, m, d);
}
