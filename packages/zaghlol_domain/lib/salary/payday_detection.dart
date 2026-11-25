// T-246 (D-81, plan section 6): the payday follows the salary. Pure rules, no
// Flutter, no database. Money is never involved: only the dates of salary
// credits in the primary currency (A10) are read.

import 'dart:convert';

import '../budget/civil_date.dart';

/// Two first-salary days within this many days are "the same day" (A5).
const int paydaySameDayTolerance = 2;

/// Months with a salary that make a pattern.
const int paydayPatternMonths = 3;

/// BR-BUD-01: the largest payday.
const int paydayMaxDay = 28;

const int paydayMaxSuppressed = 8;

/// One salary credit: its local civil date and ISO currency code.
final class PaydayCredit {
  const PaydayCredit(this.date, this.currency);
  final CivilDate date;
  final String currency;
}

/// What [detectPayday] found.
final class PaydayDetection {
  const PaydayDetection({this.day, this.apply = false});

  /// The detected payday (1..28), or null when there is no clear pattern.
  final int? day;

  /// The setting should change to [day].
  final bool apply;

  @override
  bool operator ==(Object other) =>
      other is PaydayDetection && other.day == day && other.apply == apply;

  @override
  int get hashCode => Object.hash(day, apply);

  @override
  String toString() => 'PaydayDetection($day, apply: $apply)';
}

/// A credit on this day or later belongs to the next month (A4, plan 6).
const int paydayNextMonthFromDay = 21;

/// The first salary day (capped at 28, A8) of each month, newest month first,
/// at most [paydayPatternMonths] months. A credit from day 21 on counts to
/// the next month, so 25 Oct and 5 Nov are the same month and the 25th wins.
List<int> _latestFirstDays(Iterable<PaydayCredit> credits, String currency) {
  final first = <int, CivilDate>{}; // year * 12 + month - 1 -> earliest date
  for (final c in credits) {
    if (c.currency != currency) continue;
    final key =
        c.date.year * 12 +
        c.date.month -
        1 +
        (c.date.day >= paydayNextMonthFromDay ? 1 : 0);
    final cur = first[key];
    if (cur == null || c.date.epochDay < cur.epochDay) first[key] = c.date;
  }
  final keys = first.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final k in keys.take(paydayPatternMonths))
      first[k]!.day > paydayMaxDay ? paydayMaxDay : first[k]!.day,
  ];
}

bool _agree(List<int> days) {
  final lo = days.reduce((a, b) => a < b ? a : b);
  final hi = days.reduce((a, b) => a > b ? a : b);
  return hi - lo <= paydaySameDayTolerance;
}

/// Detects the payday from [credits] (the caller passes the last 12 months).
///
/// [currentPayday] is null when the user never set one. [typedByUser] says
/// the current value was typed by hand. Only [currency] credits count (A10).
PaydayDetection detectPayday({
  required Iterable<PaydayCredit> credits,
  required String currency,
  required int? currentPayday,
  required bool typedByUser,
}) {
  final days = _latestFirstDays(credits, currency);
  if (days.isEmpty) return const PaydayDetection();
  if (!_agree(days)) return const PaydayDetection();
  final detected = days.reduce((a, b) => a < b ? a : b); // earliest wins
  if (currentPayday == null) {
    // Never set: one salary (or two or three that agree) is enough (A7).
    return PaydayDetection(day: detected, apply: true);
  }
  if (days.length < paydayPatternMonths) {
    return PaydayDetection(day: detected);
  }
  bool differs(int d) => (d - currentPayday).abs() > paydaySameDayTolerance;
  if (typedByUser) {
    // Only when every one of the 3 months disagrees (A6).
    return PaydayDetection(day: detected, apply: days.every(differs));
  }
  return PaydayDetection(day: detected, apply: differs(detected));
}

/// The memory of automatic payday changes (setting `payday_auto`).
final class PaydayAutoState {
  const PaydayAutoState({
    this.autoDay,
    this.previous,
    this.bannerPending = false,
    this.suppressed = const [],
  });

  static const PaydayAutoState empty = PaydayAutoState();

  /// The day the app last set; null when it never did.
  final int? autoDay;

  /// The value before that change; null means the payday was never set.
  final int? previous;

  /// The "I changed it" banner has not been closed yet.
  final bool bannerPending;

  /// Detected days the user undid; never auto-set again.
  final List<int> suppressed;

  /// The current payday was typed by hand (configured and not ours).
  bool typedBy(int? currentPayday) =>
      currentPayday != null && currentPayday != autoDay;

  PaydayAutoState copyWith({
    int? autoDay,
    bool clearAutoDay = false,
    int? previous,
    bool clearPrevious = false,
    bool? bannerPending,
    List<int>? suppressed,
  }) => PaydayAutoState(
    autoDay: clearAutoDay ? null : (autoDay ?? this.autoDay),
    previous: clearPrevious ? null : (previous ?? this.previous),
    bannerPending: bannerPending ?? this.bannerPending,
    suppressed: suppressed ?? this.suppressed,
  );

  PaydayAutoState withSuppressed(int day) {
    final next = [...suppressed.where((d) => d != day), day];
    return copyWith(
      suppressed: next.length > paydayMaxSuppressed
          ? next.sublist(next.length - paydayMaxSuppressed)
          : next,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaydayAutoState &&
      other.autoDay == autoDay &&
      other.previous == previous &&
      other.bannerPending == bannerPending &&
      other.suppressed.join(',') == suppressed.join(',');

  @override
  int get hashCode =>
      Object.hash(autoDay, previous, bannerPending, suppressed.join(','));

  String toJson() => jsonEncode({
    'v': 1,
    if (autoDay != null) 'a': autoDay,
    if (previous != null) 'p': previous,
    'b': bannerPending,
    's': suppressed,
  });

  /// Unreadable text reads as null.
  static PaydayAutoState? fromJson(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (j is! Map<String, Object?> || j['v'] != 1) return null;
    final a = j['a'];
    final p = j['p'];
    final b = j['b'];
    final s = j['s'];
    bool day(Object? v) => v is int && v >= 1 && v <= paydayMaxDay;
    if (a != null && !day(a)) return null;
    if (p != null && !day(p)) return null;
    if (b is! bool) return null;
    if (s is! List || s.length > paydayMaxSuppressed || !s.every(day)) {
      return null;
    }
    return PaydayAutoState(
      autoDay: a as int?,
      previous: p as int?,
      bannerPending: b,
      suppressed: List<int>.unmodifiable(s.cast<int>()),
    );
  }
}
