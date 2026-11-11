import 'dart:convert';

import 'civil_date.dart';

/// One payday setting and the date it took effect (`from` null: from the
/// beginning of time). domain-algorithms §2.
final class PaydayEra {
  /// [day] must be 1..28 (BR-BUD-01, D-68); anything else throws
  /// [ArgumentError], so month-length clamping never reaches the engine.
  PaydayEra(this.from, this.day) {
    if (day < 1 || day > 28) {
      throw ArgumentError('payday must be 1..28');
    }
  }

  final CivilDate? from;
  final int day;

  @override
  bool operator ==(Object other) =>
      other is PaydayEra && other.from == from && other.day == day;

  @override
  int get hashCode => Object.hash(from, day);

  @override
  String toString() => 'PaydayEra($from, $day)';
}

/// A payday cycle: `start..end` inclusive, local civil dates.
final class Cycle {
  const Cycle({required this.start, required this.end});

  final CivilDate start;
  final CivilDate end;

  /// The ISO start date, the key in `cycle_summaries`, `fired_alerts` and
  /// `TransactionsChanged.cycleKeys`.
  String get key => start.toIso();

  int get length => end.difference(start) + 1;

  bool contains(CivilDate d) => d >= start && d <= end;

  /// 1-based day of the cycle (payday is day 1). Outside the cycle the value
  /// is out of 1..length.
  int dayNumber(CivilDate d) => d.difference(start) + 1;

  /// Inclusive of [today], at least 1 (also after the cycle's end).
  int daysRemaining(CivilDate today) {
    final n = end.difference(today) + 1;
    return n < 1 ? 1 : n;
  }

  @override
  bool operator ==(Object other) =>
      other is Cycle && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Cycle($start..$end)';
}

/// The ordered payday eras of the user (domain-algorithms §2). Cycle starts
/// are the union, over eras, of the dates whose day-of-month is the era's day
/// and which lie in `[from_k, from_(k+1))`.
final class PaydaySchedule {
  /// [eras] must start with `from == null` and have strictly increasing
  /// `from`. Throws [ArgumentError] otherwise.
  PaydaySchedule(Iterable<PaydayEra> eras) : eras = List.unmodifiable(eras) {
    if (this.eras.isEmpty || this.eras.first.from != null) {
      throw ArgumentError('first era must have from == null');
    }
    for (var i = 1; i < this.eras.length; i++) {
      final f = this.eras[i].from;
      final prev = this.eras[i - 1].from;
      if (f == null || (prev != null && f <= prev)) {
        throw ArgumentError('eras must be strictly increasing');
      }
    }
  }

  /// A-43: no payday recorded means day 1.
  PaydaySchedule.single(int day) : this([PaydayEra(null, day)]);

  final List<PaydayEra> eras;

  int get currentDay => eras.last.day;

  /// The schedule after the user sets [day] on [today] (EC-21): appends an
  /// era from [today]; a change on the day the last era began replaces it; the
  /// same day as the current one changes nothing.
  PaydaySchedule withChange(CivilDate today, int day) {
    final next = PaydayEra(today, day);
    if (eras.last.day == day) return this;
    final head = eras.last.from == today
        ? eras.sublist(0, eras.length - 1)
        : eras;
    if (head.isEmpty) return PaydaySchedule([PaydayEra(null, day)]);
    return PaydaySchedule([...head, next]);
  }

  /// The cycle containing [date].
  Cycle cycleOn(CivilDate date) {
    final k = _eraIndexOf(date);
    final start = _startUpTo(k, date);
    return Cycle(start: start, end: _nextStartAfter(start).plusDays(-1));
  }

  /// The cycle containing the local date of the instant [utcMs].
  Cycle cycleOnMs(int utcMs, int offsetMin) =>
      cycleOn(CivilDate.fromLocalMs(utcMs, offsetMin));

  /// The cycle after [c].
  Cycle after(Cycle c) => cycleOn(c.end.plusDays(1));

  /// The cycle before [c].
  Cycle before(Cycle c) => cycleOn(c.start.plusDays(-1));

  int _eraIndexOf(CivilDate d) {
    var k = 0;
    for (var i = 1; i < eras.length; i++) {
      if (eras[i].from! <= d) k = i;
    }
    return k;
  }

  /// Greatest cycle start <= [d], looking at era [k] and, when it has none
  /// that early, the earlier eras (limited to the dates before era k).
  CivilDate _startUpTo(int k, CivilDate d) {
    final m = _lastMatch(eras[k].day, d);
    final from = eras[k].from;
    if (from == null || m >= from) return m;
    return _startUpTo(k - 1, from.plusDays(-1));
  }

  /// Smallest cycle start > [start].
  CivilDate _nextStartAfter(CivilDate start) {
    var j = _eraIndexOf(start);
    var lower = start.plusDays(1);
    while (true) {
      final cand = _firstMatch(eras[j].day, lower);
      final limit = j + 1 < eras.length ? eras[j + 1].from! : null;
      if (limit == null || cand < limit) return cand;
      j += 1;
      lower = limit;
    }
  }

  static CivilDate _firstMatch(int day, CivilDate lower) {
    final y = lower.year;
    final m = lower.month;
    if (lower.day <= day) return CivilDate(y, m, day);
    return m == 12 ? CivilDate(y + 1, 1, day) : CivilDate(y, m + 1, day);
  }

  static CivilDate _lastMatch(int day, CivilDate upper) {
    final y = upper.year;
    final m = upper.month;
    if (upper.day >= day) return CivilDate(y, m, day);
    return m == 1 ? CivilDate(y - 1, 12, day) : CivilDate(y, m - 1, day);
  }

  /// `[{"from":null|"YYYY-MM-DD","day":1..28}]` (database-schema §2.8).
  String toJson() => jsonEncode([
    for (final e in eras) {'from': e.from?.toIso(), 'day': e.day},
  ]);

  /// Null for anything that is not a valid era list (corrupt, wrong shape,
  /// out of range). Never throws, never echoes the input.
  static PaydaySchedule? tryFromJson(String text) {
    if (text.length > 16384) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List || decoded.isEmpty || decoded.length > 1000) {
        return null;
      }
      final eras = <PaydayEra>[];
      for (final e in decoded) {
        if (e is! Map || e.length != 2) return null;
        final day = e['day'];
        final from = e['from'];
        if (day is! int) return null;
        if (from == null) {
          eras.add(PaydayEra(null, day));
        } else if (from is String) {
          final d = CivilDate.tryParse(from);
          if (d == null) return null;
          eras.add(PaydayEra(d, day));
        } else {
          return null;
        }
      }
      return PaydaySchedule(eras);
    } on Object {
      return null;
    }
  }
}
