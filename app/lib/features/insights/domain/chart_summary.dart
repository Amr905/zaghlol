// T-189: the pure maths behind the redesigned charts screen: the summary
// strip (spent, income, saved, savings rate against the previous period),
// the top-5 + "Other" category fold with change chips, the compact axis
// labels and the Zaghlol one-liner choice. Integer minor units only, no
// double (CLAUDE.md §2.4); one currency per call, never summed across
// currencies. Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'chart_models.dart';
import 'chart_rules.dart';

enum ChangeDirection { up, down, same, none }

/// A change against a baseline. [value] is a whole percent (or whole
/// percentage points when [isPoints]); [none] means there is no baseline to
/// compare with (a baseline of zero).
final class ChartChange {
  const ChartChange(this.direction, this.value, {this.isPoints = false});

  static const ChartChange none = ChartChange(ChangeDirection.none, 0);
  static const ChartChange same = ChartChange(ChangeDirection.same, 0);

  final ChangeDirection direction;
  final int value;
  final bool isPoints;

  bool get isUp => direction == ChangeDirection.up;
  bool get isDown => direction == ChangeDirection.down;

  @override
  bool operator ==(Object other) =>
      other is ChartChange &&
      other.direction == direction &&
      other.value == value &&
      other.isPoints == isPoints;

  @override
  int get hashCode => Object.hash(direction, value, isPoints);

  @override
  String toString() => 'ChartChange($direction, $value, points: $isPoints)';
}

/// Whole-percent change of [current] against [previous] (both in the same
/// currency's minor units). A baseline that is zero or negative has no
/// meaningful percent: equal values are "same", anything else is [none].
ChartChange percentChange(int current, int previous) {
  if (current == previous) return ChartChange.same;
  if (previous <= 0) return ChartChange.none;
  final pct = mulDivRound(current - previous, 100, previous);
  if (pct == 0) return ChartChange.same;
  return ChartChange(
    pct > 0 ? ChangeDirection.up : ChangeDirection.down,
    pct.abs(),
  );
}

/// Income and spend of one period in one currency.
final class PeriodTotals {
  const PeriodTotals({required this.income, required this.spend});

  /// Reads the whole period out of a cash flow result (one point or more);
  /// a period without rows is zero.
  factory PeriodTotals.fromCashFlow(
    ChartResult<List<CashFlowPoint>> result,
    Currency currency,
  ) => switch (result) {
    ChartReady<List<CashFlowPoint>>(:final data) when data.isNotEmpty => () {
      final t = CashFlowPoint.total(data);
      return PeriodTotals(income: t.income, spend: t.spend);
    }(),
    _ => PeriodTotals(income: Money(currency, 0), spend: Money(currency, 0)),
  };

  final Money income;
  final Money spend;

  Money get saved => income - spend;

  /// Saved over income as a whole percent (half away from zero); null when
  /// there was no income.
  int? get ratePct =>
      income.minor > 0 ? mulDivRound(saved.minor, 100, income.minor) : null;

  bool get isEmpty => income.minor == 0 && spend.minor == 0;
}

/// The summary strip: the four figures and their change vs the previous
/// period (one currency).
final class ChartSummary {
  ChartSummary._({
    required this.current,
    required this.previous,
    required this.spentChange,
    required this.incomeChange,
    required this.savedChange,
    required this.rateChange,
  });

  factory ChartSummary.compute(PeriodTotals current, PeriodTotals previous) {
    final rate = current.ratePct;
    final prevRate = previous.ratePct;
    ChartChange rateChange;
    if (rate == null || prevRate == null) {
      rateChange = ChartChange.none;
    } else if (rate == prevRate) {
      rateChange = ChartChange.same;
    } else {
      rateChange = ChartChange(
        rate > prevRate ? ChangeDirection.up : ChangeDirection.down,
        (rate - prevRate).abs(),
        isPoints: true,
      );
    }
    return ChartSummary._(
      current: current,
      previous: previous,
      spentChange: percentChange(current.spend.minor, previous.spend.minor),
      incomeChange: percentChange(current.income.minor, previous.income.minor),
      savedChange: percentChange(current.saved.minor, previous.saved.minor),
      rateChange: rateChange,
    );
  }

  final PeriodTotals current;
  final PeriodTotals previous;
  final ChartChange spentChange;
  final ChartChange incomeChange;
  final ChartChange savedChange;
  final ChartChange rateChange;

  Money get spent => current.spend;
  Money get income => current.income;
  Money get saved => current.saved;
  int? get ratePct => current.ratePct;

  /// Nothing to summarise yet.
  bool get isEmpty => current.isEmpty;
}

// ------------------------------------------------------ top 5 + "Other"

/// One entry of the donut: a category, or the folded "Other".
final class DonutEntry {
  const DonutEntry({
    required this.categoryId,
    required this.isOther,
    required this.amount,
    required this.shareBp,
    required this.count,
    required this.change,
    this.memberIds = const [],
  });

  /// The categories behind the entry: one for a named slice, all folded ones
  /// for "Other" (a null among them is uncategorized).
  final List<String?> memberIds;

  /// Null for uncategorized and for the folded "Other".
  final String? categoryId;
  final bool isOther;
  final Money amount;
  final int shareBp;
  final int count;

  /// Against the previous period; [ChartChange.none] for "Other".
  final ChartChange change;
}

/// How many categories the donut names before folding the rest.
const int donutTopCount = 5;

/// The [top] largest slices plus one folded "Other" entry (when there are
/// more); each named entry carries its change against [previous]. Amounts and
/// shares of the folded entries add up to the donut's. Ties keep the
/// donut's order.
List<DonutEntry> topCategoriesPlusOther(
  CategoryDonut donut, {
  CategoryDonut? previous,
  int top = donutTopCount,
}) {
  final indexed = [for (var i = 0; i < donut.slices.length; i++) i];
  indexed.sort((a, b) {
    final c = donut.slices[b].amount.compareTo(donut.slices[a].amount);
    return c != 0 ? c : a.compareTo(b);
  });
  final head = [for (final i in indexed.take(top)) donut.slices[i]];
  final tail = [for (final i in indexed.skip(top)) donut.slices[i]];
  int prevOf(String? id) {
    if (previous == null) return 0;
    for (final s in previous.slices) {
      if (s.categoryId == id) return s.amount.minor;
    }
    return 0;
  }

  final out = [
    for (final s in head)
      DonutEntry(
        categoryId: s.categoryId,
        isOther: false,
        memberIds: [s.categoryId],
        amount: s.amount,
        shareBp: s.shareBp,
        count: s.count,
        change: previous == null
            ? ChartChange.none
            : percentChange(s.amount.minor, prevOf(s.categoryId)),
      ),
  ];
  if (tail.isNotEmpty) {
    out.add(
      DonutEntry(
        categoryId: null,
        isOther: true,
        memberIds: [for (final s in tail) s.categoryId],
        amount: tail.map((s) => s.amount).reduce((a, b) => a + b),
        shareBp: tail.fold<int>(0, (n, s) => n + s.shareBp),
        count: tail.fold<int>(0, (n, s) => n + s.count),
        change: ChartChange.none,
      ),
    );
  }
  return out;
}

// --------------------------------------------------------- Zaghlol line

enum ChartInsightKind {
  /// Spending is down, but one category is up.
  downWithRiser,
  down,
  upWithRiser,
  up,
  same,

  /// No baseline (nothing in the previous period) or no spending yet.
  noBaseline,
}

final class ChartInsight {
  const ChartInsight(this.kind, {this.riserId, this.riserPct = 0});
  final ChartInsightKind kind;

  /// The category that rose the most (a named one, not "Other").
  final String? riserId;
  final int riserPct;
}

/// Picks the one-liner for the summary: total spend direction, plus the
/// named category with the biggest rise when there is one.
ChartInsight pickInsight(ChartSummary summary, List<DonutEntry> entries) {
  DonutEntry? riser;
  for (final e in entries) {
    if (e.isOther || e.categoryId == null || !e.change.isUp) continue;
    if (riser == null || e.change.value > riser.change.value) riser = e;
  }
  final c = summary.spentChange;
  switch (c.direction) {
    case ChangeDirection.none:
      return const ChartInsight(ChartInsightKind.noBaseline);
    case ChangeDirection.same:
      return const ChartInsight(ChartInsightKind.same);
    case ChangeDirection.down:
      return riser == null
          ? const ChartInsight(ChartInsightKind.down)
          : ChartInsight(
              ChartInsightKind.downWithRiser,
              riserId: riser.categoryId,
              riserPct: riser.change.value,
            );
    case ChangeDirection.up:
      return riser == null
          ? const ChartInsight(ChartInsightKind.up)
          : ChartInsight(
              ChartInsightKind.upWithRiser,
              riserId: riser.categoryId,
              riserPct: riser.change.value,
            );
  }
}

// ------------------------------------------------------ axis (value scale)

/// A "nice" step for a value axis that spans [maxMinor] in about three
/// gridlines: 1, 2, 2.5 or 5 times a power of ten, never below 1.
int niceAxisStep(int maxMinor) {
  if (maxMinor <= 0) return 1;
  final raw = (maxMinor + 2) ~/ 3;
  var pow = 1;
  while (pow * 10 <= raw) {
    pow *= 10;
  }
  // Candidates as 10 * mantissa to keep integers: 10, 20, 25, 50, 100.
  for (final m in const [10, 20, 25, 50, 100]) {
    final step = pow * m ~/ 10;
    if (step >= raw && step >= 1) return step;
  }
  return pow * 10;
}

/// The top gridline: [maxMinor] rounded up to a multiple of [step].
int axisTop(int maxMinor, int step) =>
    maxMinor <= 0 ? step : ((maxMinor + step - 1) ~/ step) * step;

enum CompactUnit { none, thousand, million }

/// An amount as a short axis label: [tenths] tenths of [unit] (12 with
/// thousand is 1.2K).
final class CompactAmount {
  const CompactAmount(this.tenths, this.unit);
  final int tenths;
  final CompactUnit unit;

  int get whole => tenths ~/ 10;
  int get fraction => tenths % 10;

  @override
  bool operator ==(Object other) =>
      other is CompactAmount && other.tenths == tenths && other.unit == unit;

  @override
  int get hashCode => Object.hash(tenths, unit);

  @override
  String toString() => 'CompactAmount($tenths, $unit)';
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// [minor] (in a currency with [exponent] decimals) as a compact label:
/// below 1000 whole units, then thousands, then millions, one decimal at
/// most. Negative amounts keep their sign on the number.
CompactAmount compactAmount(int minor, int exponent) {
  final unitMinor = _pow10(exponent);
  final abs = minor.abs();
  final sign = minor < 0 ? -1 : 1;
  CompactAmount build(int divisorMajor, CompactUnit unit) => CompactAmount(
    sign * mulDivRound(abs, 10, unitMinor * divisorMajor),
    unit,
  );
  if (abs >= unitMinor * 1000000) return build(1000000, CompactUnit.million);
  if (abs >= unitMinor * 1000) {
    final k = build(1000, CompactUnit.thousand);
    // 999.96K rounds to 1000.0K: that is 1.0M.
    if (k.tenths.abs() >= 10000) return build(1000000, CompactUnit.million);
    return k;
  }
  // Whole units, no decimal: tenths is a multiple of ten.
  return CompactAmount(
    sign * mulDivRound(abs, 1, unitMinor) * 10,
    CompactUnit.none,
  );
}
