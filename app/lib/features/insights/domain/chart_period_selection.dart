// T-188 (FR-CHT-04, D-68): the period the user picks for the charts. Pure
// Dart; Gregorian dates only (CivilDate). A selection holds a preset, a
// step offset and, for the custom preset, a range. It holds no resolved
// dates for relative presets, so it re-resolves when the date changes.
// Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'chart_models.dart';

enum ChartPreset {
  thisCycle,
  lastCycle,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  last12Months,
  thisYear,
  custom,
}

/// How a preset moves when stepped.
enum ChartPeriodKind { cycle, month, rolling, year, custom }

/// The bucket size of a chart that plots over time.
enum ChartBucketKind { day, week, month }

/// How a chart relates to the chosen period.
enum ChartPeriodSupport {
  /// Any period.
  any,

  /// One payday cycle (and the cycles before it); other kinds show a note.
  cycleOnly,

  /// Not a period chart (fixed horizon or the current budget cycle).
  fixed,
}

abstract final class ChartPeriodLimits {
  /// A custom range is at most five years (guards the queries).
  static const int maxCustomDays = 1827;

  /// Stepping never goes before this date.
  static final CivilDate earliest = CivilDate(2000, 1, 1);

  /// Stored offsets outside this range are rejected.
  static const int minOffset = -12;
  static const int maxOffset = 120;

  /// Day buckets up to this many days, then weeks.
  static const int dayBucketMaxDays = 31;

  /// Week buckets up to this many days (about six months), then months.
  static const int weekBucketMaxDays = 190;

  /// Net worth is drawn over at least this many months.
  static const int netWorthMinMonths = 12;
}

int _monthIndex(CivilDate d) => d.year * 12 + d.month - 1;
CivilDate _firstOfMonth(int index) => CivilDate(index ~/ 12, index % 12 + 1, 1);

final class ChartPeriodSelection {
  /// A preset other than [ChartPreset.custom]; [offset] counts steps back
  /// (negative: forward).
  const ChartPeriodSelection(this.preset, {this.offset = 0})
    : customFrom = null,
      customTo = null,
      assert(preset != ChartPreset.custom);

  const ChartPeriodSelection._custom(
    this.customFrom,
    this.customTo,
    this.offset,
  ) : preset = ChartPreset.custom;

  /// A custom range; throws [ArgumentError] when [from] is after [to] or the
  /// range is longer than [ChartPeriodLimits.maxCustomDays].
  factory ChartPeriodSelection.custom(
    CivilDate from,
    CivilDate to, {
    int offset = 0,
  }) {
    if (to < from ||
        to.difference(from) + 1 > ChartPeriodLimits.maxCustomDays) {
      throw ArgumentError('invalid custom range');
    }
    return ChartPeriodSelection._custom(from, to, offset);
  }

  static const ChartPeriodSelection thisCycle = ChartPeriodSelection(
    ChartPreset.thisCycle,
  );

  final ChartPreset preset;
  final int offset;
  final CivilDate? customFrom;
  final CivilDate? customTo;

  ChartPeriodKind get kind => switch (preset) {
    ChartPreset.thisCycle || ChartPreset.lastCycle => ChartPeriodKind.cycle,
    ChartPreset.thisMonth || ChartPreset.lastMonth => ChartPeriodKind.month,
    ChartPreset.last3Months ||
    ChartPreset.last6Months ||
    ChartPreset.last12Months => ChartPeriodKind.rolling,
    ChartPreset.thisYear => ChartPeriodKind.year,
    ChartPreset.custom => ChartPeriodKind.custom,
  };

  /// Months of a rolling preset; 0 for the others.
  int get rollingMonths => switch (preset) {
    ChartPreset.last3Months => 3,
    ChartPreset.last6Months => 6,
    ChartPreset.last12Months => 12,
    _ => 0,
  };

  int get _base =>
      preset == ChartPreset.lastCycle || preset == ChartPreset.lastMonth
      ? 1
      : 0;

  /// Periods before the current one of the same kind (0: the current).
  /// Meaningless for custom.
  int get periodsBack => _base + offset;

  /// The same selection moved [delta] steps back (negative: forward).
  /// Unchanged when the result would leave the stored offset range.
  ChartPeriodSelection stepped(int delta) {
    final next = offset + delta;
    if (next < ChartPeriodLimits.minOffset ||
        next > ChartPeriodLimits.maxOffset) {
      return this;
    }
    return preset == ChartPreset.custom
        ? ChartPeriodSelection._custom(customFrom, customTo, next)
        : ChartPeriodSelection(preset, offset: next);
  }

  /// The period on [today] under [schedule] (payday eras).
  ChartPeriod resolve(CivilDate today, PaydaySchedule schedule) {
    switch (kind) {
      case ChartPeriodKind.cycle:
        var c = schedule.cycleOn(today);
        for (var i = 0; i < periodsBack; i++) {
          c = schedule.before(c);
        }
        for (var i = 0; i > periodsBack; i--) {
          c = schedule.after(c);
        }
        return ChartPeriod.cycle(c);
      case ChartPeriodKind.month:
        final idx = _monthIndex(today) - periodsBack;
        return ChartPeriod.month(idx ~/ 12, idx % 12 + 1);
      case ChartPeriodKind.rolling:
        final n = rollingMonths;
        final s0 = _monthIndex(today) - (n - 1);
        if (offset == 0) return ChartPeriod(_firstOfMonth(s0), today);
        return ChartPeriod(
          _firstOfMonth(s0 - offset * n),
          _firstOfMonth(s0 - (offset - 1) * n).plusDays(-1),
        );
      case ChartPeriodKind.year:
        final y = today.year - offset;
        return ChartPeriod(CivilDate(y, 1, 1), CivilDate(y, 12, 31));
      case ChartPeriodKind.custom:
        final from = customFrom!;
        final to = customTo!;
        final shift = -offset * (to.difference(from) + 1);
        return ChartPeriod(from.plusDays(shift), to.plusDays(shift));
    }
  }

  bool canStepBack(CivilDate today, PaydaySchedule schedule) {
    final next = stepped(1);
    if (identical(next, this)) return false;
    return next.resolve(today, schedule).from >= ChartPeriodLimits.earliest;
  }

  /// Forward is allowed while the next period has started (its first day is
  /// today or earlier).
  bool canStepForward(CivilDate today, PaydaySchedule schedule) {
    if (kind != ChartPeriodKind.custom && periodsBack <= 0) return false;
    final next = stepped(-1);
    if (identical(next, this)) return false;
    return next.resolve(today, schedule).from <= today;
  }

  /// The selection resolved on [today]: the period, the previous period of
  /// the same kind and what stepping can do.
  ResolvedChartPeriod resolveAll(CivilDate today, PaydaySchedule schedule) =>
      ResolvedChartPeriod._(
        selection: this,
        period: resolve(today, schedule),
        previous: stepped(1).resolve(today, schedule),
        canStepBack: canStepBack(today, schedule),
        canStepForward: canStepForward(today, schedule),
      );

  /// Storage text: `<preset>|<offset>|<from>|<to>` (dates only for custom).
  String encode() =>
      '${preset.name}|$offset|${customFrom?.toIso() ?? ''}|'
      '${customTo?.toIso() ?? ''}';

  /// Strict inverse of [encode]; null for anything else (unknown preset,
  /// bad numbers or dates, a custom range that is invalid, extra fields).
  static ChartPeriodSelection? tryDecode(String text) {
    if (text.length > 64) return null;
    final parts = text.split('|');
    if (parts.length != 4) return null;
    ChartPreset? preset;
    for (final p in ChartPreset.values) {
      if (p.name == parts[0]) preset = p;
    }
    if (preset == null || !RegExp(r'^-?[0-9]{1,3}$').hasMatch(parts[1])) {
      return null;
    }
    final offset = int.parse(parts[1]);
    if (offset < ChartPeriodLimits.minOffset ||
        offset > ChartPeriodLimits.maxOffset) {
      return null;
    }
    if (preset != ChartPreset.custom) {
      if (parts[2].isNotEmpty || parts[3].isNotEmpty) return null;
      return ChartPeriodSelection(preset, offset: offset);
    }
    final from = CivilDate.tryParse(parts[2]);
    final to = CivilDate.tryParse(parts[3]);
    if (from == null || to == null) return null;
    try {
      return ChartPeriodSelection.custom(from, to, offset: offset);
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChartPeriodSelection &&
      other.preset == preset &&
      other.offset == offset &&
      other.customFrom == customFrom &&
      other.customTo == customTo;

  @override
  int get hashCode => Object.hash(preset, offset, customFrom, customTo);

  @override
  String toString() => 'ChartPeriodSelection(${encode()})';
}

/// A selection resolved against today's date and the payday schedule.
final class ResolvedChartPeriod {
  const ResolvedChartPeriod._({
    required this.selection,
    required this.period,
    required this.previous,
    required this.canStepBack,
    required this.canStepForward,
  });

  final ChartPeriodSelection selection;
  final ChartPeriod period;

  /// The period one step back: the previous cycle, month, block of months,
  /// year, or a custom range's own length earlier (FR-CHT-08 compares with it).
  final ChartPeriod previous;
  final bool canStepBack;
  final bool canStepForward;

  ChartPeriodKind get kind => selection.kind;

  bool get isCycle => kind == ChartPeriodKind.cycle;

  /// The current payday cycle (the budget chart's own period).
  bool get isCurrentCycle => isCycle && selection.periodsBack == 0;

  /// The period as a payday cycle (burn rate, month vs average); null when
  /// the selection is not a cycle.
  Cycle? get cycle =>
      isCycle ? Cycle(start: period.from, end: period.to) : null;

  ChartBucketKind get bucketKind => bucketKindFor(period);

  /// How the chart [chart] treats this period.
  bool supports(ChartId chart) =>
      chartPeriodSupport(chart) != ChartPeriodSupport.cycleOnly || isCycle;
}

/// Which charts follow the period (design note §3).
ChartPeriodSupport chartPeriodSupport(ChartId chart) => switch (chart) {
  ChartId.burnCurve || ChartId.monthVsAverage => ChartPeriodSupport.cycleOnly,
  ChartId.installmentTimeline ||
  ChartId.subscriptionsAnnual ||
  ChartId.personalInflation ||
  ChartId.budgetProgress => ChartPeriodSupport.fixed,
  _ => ChartPeriodSupport.any,
};

/// Day buckets up to 31 days, weeks up to about six months, then months.
ChartBucketKind bucketKindFor(ChartPeriod p) {
  final n = p.lengthDays;
  if (n <= ChartPeriodLimits.dayBucketMaxDays) return ChartBucketKind.day;
  if (n <= ChartPeriodLimits.weekBucketMaxDays) return ChartBucketKind.week;
  return ChartBucketKind.month;
}

/// The buckets of [p] in order, without any that start after [today]. They
/// partition the part of [p] up to the last bucket's end (day, 7-day chunk
/// or calendar month, clipped to the range).
List<ChartPeriod> bucketsOf(ChartPeriod p, CivilDate today) {
  final out = <ChartPeriod>[];
  switch (bucketKindFor(p)) {
    case ChartBucketKind.day:
      for (var d = p.from; d <= p.to; d = d.plusDays(1)) {
        out.add(ChartPeriod(d, d));
      }
    case ChartBucketKind.week:
      for (var s = p.from; s <= p.to; s = s.plusDays(7)) {
        final e = s.plusDays(6);
        out.add(ChartPeriod(s, e > p.to ? p.to : e));
      }
    case ChartBucketKind.month:
      var s = p.from;
      while (s <= p.to) {
        final end = CivilDate(
          s.year,
          s.month,
          CivilDate.daysInMonth(s.year, s.month),
        );
        out.add(ChartPeriod(s, end > p.to ? p.to : end));
        s = end.plusDays(1);
      }
  }
  final kept = [
    for (final b in out)
      if (b.from <= today) b,
  ];
  return kept.isEmpty ? [out.first] : kept;
}

/// The net worth range: the period, widened to at least 12 months ending at
/// its end ("may extend", design note §3).
ChartPeriod netWorthRange(ChartPeriod p) {
  final minStart = _firstOfMonth(
    _monthIndex(p.to) - (ChartPeriodLimits.netWorthMinMonths - 1),
  );
  return ChartPeriod(p.from < minStart ? p.from : minStart, p.to);
}
