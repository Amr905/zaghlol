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
  return null;
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
