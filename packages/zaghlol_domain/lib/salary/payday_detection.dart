// T-246 (D-81, plan section 6): the payday follows the salary. Pure rules, no
// Flutter, no database. Money is never involved: only the dates and currency
// codes of salary credits are read. T-271 (D-85): the credits of the user's
// salary currency count, which is the primary currency only on a tie.

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
  const PaydayDetection({this.day, this.apply = false, this.salaryDay});

  /// The detected payday (1..28), or null when there is no clear pattern.
  final int? day;

  /// The setting should change to [day].
  final bool apply;

  /// The real day of the month the salary lands (1..31): differs from [day]
  /// when a salary on 29..31 was capped to 28.
  final int? salaryDay;

  @override
  bool operator ==(Object other) =>
      other is PaydayDetection &&
      other.day == day &&
      other.apply == apply &&
      other.salaryDay == salaryDay;

  @override
  int get hashCode => Object.hash(day, apply, salaryDay);

  @override
  String toString() => 'PaydayDetection($day, apply: $apply)';
}

/// A credit on this day or later belongs to the next month (A4, plan 6).
const int paydayNextMonthFromDay = 21;

/// Days of the ring the month end and month start sit on (capped days 1..28):
/// 28 and 1 are neighbours so a weekend shift over the month end still
/// agrees (FU-296 m-3).
const int _ring = paydayMaxDay;

/// The first salary date of each month, newest month first, at most
/// [paydayPatternMonths] months. A credit from day 21 on counts to the next
/// month, so 25 Oct and 5 Nov are the same month and the 25th wins.
int _monthKey(CivilDate d) =>
    d.year * 12 + d.month - 1 + (d.day >= paydayNextMonthFromDay ? 1 : 0);

/// T-271 (D-85): the user's salary currency. Among the salary months of the
/// latest [paydayPatternMonths] months (any currency), the currency with the
/// most months wins. A tie goes to [primary] when it is among the tied; else
/// to the currency with the newest credit (then the smaller code), so the
/// answer never depends on input order. Null when there are no credits.
String? salaryCurrencyOf(Iterable<PaydayCredit> credits, String primary) {
  final months = <String, Set<int>>{};
  final newest = <String, int>{};
  final all = <int>{};
  for (final c in credits) {
    final k = _monthKey(c.date);
    all.add(k);
    (months[c.currency] ??= {}).add(k);
    final e = c.date.epochDay;
    if (e > (newest[c.currency] ?? -1000000000)) newest[c.currency] = e;
  }
  if (months.isEmpty) return null;
  final latest = (all.toList()..sort((a, b) => b.compareTo(a)))
      .take(paydayPatternMonths)
      .toSet();
  final count = {
    for (final e in months.entries)
      e.key: e.value.where(latest.contains).length,
  };
  final top = count.values.reduce((a, b) => a > b ? a : b);
  final tied = [
    for (final e in count.entries)
      if (e.value == top) e.key,
  ];
  if (tied.length == 1) return tied.single;
  if (tied.contains(primary)) return primary;
  tied.sort((a, b) {
    final byNew = newest[b]!.compareTo(newest[a]!);
    return byNew != 0 ? byNew : a.compareTo(b);
  });
  return tied.first;
}

List<int> _latestFirstDays(Iterable<PaydayCredit> credits, String currency) {
  final first = <int, CivilDate>{}; // year * 12 + month - 1 -> earliest date
  for (final c in credits) {
    if (c.currency != currency) continue;
    final key = _monthKey(c.date);
    final cur = first[key];
    if (cur == null || c.date.epochDay < cur.epochDay) first[key] = c.date;
  }
  final keys = first.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys.take(paydayPatternMonths)) first[k]!.day];
}

int _cap(int day) => day > paydayMaxDay ? paydayMaxDay : day;

/// Steps forward from [from] to [to] around the ring (0..27).
int _forward(int from, int to) => (to - from) % _ring;

/// The shortest arc of the ring holding every day: where it starts and how
/// many days it spans.
({int start, int span}) _arc(List<int> days) {
  var best = (start: days.first, span: _ring);
  for (final s in days) {
    final span = days
        .map((d) => _forward(s, d))
        .reduce((a, b) => a > b ? a : b);
    if (span < best.span || (span == best.span && s < best.start)) {
      best = (start: s, span: span);
    }
  }
  return best;
}

int _ringDistance(int a, int b) {
  final d = _forward(a, b);
  return d < _ring - d ? d : _ring - d;
}

/// Detects the payday from [credits] (the caller passes the last 12 months).
///
/// [currentPayday] is null when the user never set one. [typedByUser] says
/// the current value was typed by hand. Only [currency] credits count; use
/// [detectPaydayForSalary] to pick the user's salary currency first.
PaydayDetection detectPayday({
  required Iterable<PaydayCredit> credits,
  required String currency,
  required int? currentPayday,
  required bool typedByUser,
}) {
  final raw = _latestFirstDays(credits, currency);
  if (raw.isEmpty) return const PaydayDetection();
  final days = [for (final d in raw) _cap(d)]; // A8
  final arc = _arc(days);
  if (arc.span > paydaySameDayTolerance) return const PaydayDetection();
  // The earliest day of the pattern wins; the real salary day behind it is
  // the smallest actual day (29..31 are capped to 28 for the payday).
  final detected = arc.start;
  final salaryDay = [
    for (var i = 0; i < raw.length; i++)
      if (days[i] == detected) raw[i],
  ].reduce((a, b) => a < b ? a : b);
  if (currentPayday == null) {
    // Never set: one salary (or two or three that agree) is enough (A7).
    return PaydayDetection(day: detected, apply: true, salaryDay: salaryDay);
  }
  if (days.length < paydayPatternMonths) {
    return PaydayDetection(day: detected, salaryDay: salaryDay);
  }
  bool differs(int d) =>
      _ringDistance(d, currentPayday) > paydaySameDayTolerance;
  if (typedByUser) {
    // Only when every one of the 3 months disagrees (A6).
    return PaydayDetection(
      day: detected,
      apply: days.every(differs),
      salaryDay: salaryDay,
    );
  }
  return PaydayDetection(
    day: detected,
    apply: differs(detected),
    salaryDay: salaryDay,
  );
}

/// The memory of automatic payday changes (setting `payday_auto`).
final class PaydayAutoState {
  const PaydayAutoState({
    this.autoDay,
    this.previous,
    this.previousEras,
    this.salaryDay,
    this.bannerPending = false,
    this.suppressed = const [],
  });

  static const PaydayAutoState empty = PaydayAutoState();

  /// The day the app last set; null when it never did.
  final int? autoDay;

  /// The value before that change; null means the payday was never set.
  final int? previous;

  /// The `payday_eras` text from before that change; null when none was set.
  final String? previousEras;

  /// The real day the salary lands (1..31) behind [autoDay]; null for state
  /// saved before this was kept (the banner then names [autoDay]).
  final int? salaryDay;

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
    String? previousEras,
    int? salaryDay,
    bool? bannerPending,
    List<int>? suppressed,
  }) => PaydayAutoState(
    autoDay: clearAutoDay ? null : (autoDay ?? this.autoDay),
    previous: clearPrevious ? null : (previous ?? this.previous),
    previousEras: clearPrevious ? null : (previousEras ?? this.previousEras),
    salaryDay: clearAutoDay ? null : (salaryDay ?? this.salaryDay),
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
      other.previousEras == previousEras &&
      other.salaryDay == salaryDay &&
      other.bannerPending == bannerPending &&
      other.suppressed.join(',') == suppressed.join(',');

  @override
  int get hashCode => Object.hash(
    autoDay,
    previous,
    previousEras,
    salaryDay,
    bannerPending,
    suppressed.join(','),
  );

  String toJson() => jsonEncode({
    'v': 1,
    if (autoDay != null) 'a': autoDay,
    if (previous != null) 'p': previous,
    if (previousEras != null) 'e': previousEras,
    if (salaryDay != null) 'd': salaryDay,
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
    final e = j['e'];
    final d = j['d'];
    final b = j['b'];
    final s = j['s'];
    bool day(Object? v) => v is int && v >= 1 && v <= paydayMaxDay;
    if (a != null && !day(a)) return null;
    if (p != null && !day(p)) return null;
    if (e != null && (e is! String || e.length > 16384)) return null;
    if (d != null && (d is! int || d < 1 || d > 31)) return null;
    if (b is! bool) return null;
    if (s is! List || s.length > paydayMaxSuppressed || !s.every(day)) {
      return null;
    }
    return PaydayAutoState(
      autoDay: a as int?,
      previous: p as int?,
      previousEras: e as String?,
      salaryDay: d as int?,
      bannerPending: b,
      suppressed: List<int>.unmodifiable(s.cast<int>()),
    );
  }
}

/// T-271 (D-85): [detectPayday] on the credits of the user's salary currency
/// ([salaryCurrencyOf]; [primaryCurrency] breaks ties).
PaydayDetection detectPaydayForSalary({
  required Iterable<PaydayCredit> credits,
  required String primaryCurrency,
  required int? currentPayday,
  required bool typedByUser,
}) {
  final list = credits.toList();
  final currency = salaryCurrencyOf(list, primaryCurrency);
  if (currency == null) return const PaydayDetection();
  return detectPayday(
    credits: list,
    currency: currency,
    currentPayday: currentPayday,
    typedByUser: typedByUser,
  );
}
