// T-105: the vocabulary of the chart query layer (FR-CHT-01/04/05/06). Pure
// Dart. Every figure is a `Money` in ONE currency: a query takes the
// currency it answers in and never adds two currencies (CLAUDE.md §2.4).
// Only the labelled "≈" view (`approxChartTotal`) combines currencies.
// Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// The charts, in the order of SRS FR-CHT-01, plus the budget progress bars
/// (A-06), which are the fourth Free chart and are served by T-095.
enum ChartId {
  cashFlow,
  categoryDonut,
  burnCurve,
  fiftyThirtyTwenty,
  dayHourPattern,
  topMerchants,
  monthVsAverage,
  installmentTimeline,
  subscriptionsAnnual,
  cardsSplit,
  netWorth,
  personalInflation,
  budgetProgress,
}

/// A local-date range, both ends inclusive (FR-CHT-04: cycle, month or
/// custom range).
final class ChartPeriod {
  ChartPeriod(this.from, this.to) {
    if (to < from) throw ArgumentError('period ends before it starts');
  }

  factory ChartPeriod.cycle(Cycle cycle) => ChartPeriod(cycle.start, cycle.end);

  /// The calendar month [month] (1..12) of [year].
  factory ChartPeriod.month(int year, int month) => ChartPeriod(
    CivilDate(year, month, 1),
    CivilDate(year, month, CivilDate.daysInMonth(year, month)),
  );

  final CivilDate from;
  final CivilDate to;

  int get lengthDays => to.difference(from) + 1;

  bool contains(CivilDate d) => d >= from && d <= to;

  String get key => '${from.toIso()}..${to.toIso()}';

  @override
  bool operator ==(Object other) =>
      other is ChartPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'ChartPeriod($key)';
}

/// Card/account and currency filter (FR-CHT-05). [accountIds] empty is all
/// accounts. [currency] is required: a chart never mixes currencies.
final class ChartFilter {
  ChartFilter({required this.currency, Set<String> accountIds = const {}})
    : accountIds = Set.unmodifiable(accountIds);

  final Currency currency;
  final Set<String> accountIds;

  String get key {
    final ids = accountIds.toList()..sort();
    return '${currency.code}|${ids.join(',')}';
  }
}

/// Why a chart has nothing to draw yet (EC-23).
enum NotEnoughReason {
  /// No matching transaction (or asset, item or snapshot) at all.
  noData,

  /// Some data, fewer rows than the chart needs.
  tooFewTransactions,

  /// An average needs more complete earlier cycles (EC-23).
  tooFewCycles,

  tooFewSnapshots,
  tooFewMerchants,

  /// 50/30/20 is a share of income.
  noIncome,
}

/// A chart's result: data, or the "not enough data" state (EC-23). [have]
/// and [need] are in the unit of the reason (rows, cycles, snapshots...).
sealed class ChartResult<T> {
  const ChartResult();
}

final class ChartReady<T> extends ChartResult<T> {
  const ChartReady(this.data);
  final T data;
}

final class ChartNotEnoughData<T> extends ChartResult<T> {
  const ChartNotEnoughData(
    this.reason, {
    required this.have,
    required this.need,
  });
  final NotEnoughReason reason;
  final int have;
  final int need;
}

/// Minimums behind the "not enough data" states.
abstract final class ChartThresholds {
  /// Day/hour pattern: fewer spend rows say nothing about a habit.
  static const int dayHourMinTransactions = 10;

  /// Burn curve projection needs this many elapsed days (EC-23).
  static const int projectionMinDays = 3;

  /// Month vs average: complete earlier cycles needed (EC-23). A cycle is
  /// complete when the user's first transaction is on or before its start.
  static const int averageMinCycles = 2;
  static const int averageMaxCycles = 3;

  /// Net worth line.
  static const int netWorthMinSnapshots = 2;

  /// Personal inflation: merchants seen in at least two months, in the
  /// currency.
  static const int inflationMinMerchants = 3;
  static const int inflationMonths = 12;

  /// Free users see the top 5 merchants (FR-CHT-02).
  static const int freeTopMerchants = 5;
}

// ---------------------------------------------------------------- 1 cash flow

final class CashFlowPoint {
  const CashFlowPoint({
    required this.period,
    required this.income,
    required this.spend,
    required this.isPartial,
  });

  final ChartPeriod period;
  final Money income;
  final Money spend;

  /// The user's data starts inside this bucket (EC-23): shown as partial.
  final bool isPartial;

  Money get net => income - spend;
}

// ---------------------------------------------------------- 2 category donut

final class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.amount,
    required this.shareBp,
    required this.count,
  });

  /// Null: uncategorized.
  final String? categoryId;
  final Money amount;

  /// Share of the total in basis points (10000 = 100%); the slices of one
  /// donut add up to exactly 10000 (largest remainder).
  final int shareBp;
  final int count;
}

final class CategoryDonut {
  const CategoryDonut({required this.total, required this.slices});
  final Money total;
  final List<CategorySlice> slices;
}

// ----------------------------------------------------------- 3 burn curve

final class BurnCurve {
  const BurnCurve({
    required this.cycle,
    required this.elapsedDays,
    required this.cumulative,
    required this.budget,
    required this.projectedTotal,
  });

  final Cycle cycle;

  /// Days of the cycle that have started (1..length).
  final int elapsedDays;

  /// Cumulative net spend at the end of cycle day 1..[elapsedDays].
  final List<Money> cumulative;

  /// The cycle budget basis in this currency, or null (no budget).
  final Money? budget;

  /// Straight-line projection to the end of the cycle; null before
  /// [ChartThresholds.projectionMinDays] days.
  final Money? projectedTotal;

  /// The budget's even-pace line at the end of cycle day [day] (1-based);
  /// null without a budget.
  Money? idealAt(int day) => budget == null
      ? null
      : Money(budget!.currency, (budget!.minor * day) ~/ cycle.length);
}

// ------------------------------------------------------------ 4 50/30/20

final class FiftyThirtyTwenty {
  const FiftyThirtyTwenty({
    required this.income,
    required this.needs,
    required this.wants,
    required this.savings,
    required this.other,
  });

  /// Net income of the period.
  final Money income;

  /// Needs and obligations buckets.
  final Money needs;
  final Money wants;

  /// Savings-bucket spend plus unspent income (never negative).
  final Money savings;

  /// Giving, income-bucket and uncategorized spend: shown, not judged.
  final Money other;

  static const int targetNeedsBp = 5000;
  static const int targetWantsBp = 3000;
  static const int targetSavingsBp = 2000;

  /// Share of [income] in basis points (rounded half up).
  int shareBp(Money part) => income.minor <= 0
      ? 0
      : (part.minor * 10000 + income.minor ~/ 2) ~/ income.minor;
}

// ------------------------------------------------------ 5 day / hour pattern

final class DayHourCell {
  const DayHourCell({required this.spend, required this.count});
  final Money spend;
  final int count;
}

final class DayHourPattern {
  const DayHourPattern({required this.byWeekday, required this.byHour});

  /// ISO weekday 1 (Monday) .. 7 (Sunday) -> cell; always 7 entries.
  final Map<int, DayHourCell> byWeekday;

  /// Local hour 0..23 -> cell; always 24 entries.
  final Map<int, DayHourCell> byHour;
}

// --------------------------------------------------------- 6 top merchants

final class MerchantSpend {
  const MerchantSpend({
    required this.merchantNorm,
    required this.name,
    required this.amount,
    required this.count,
  });

  final String merchantNorm;
  final String name;
  final Money amount;
  final int count;
}

// --------------------------------------------------- 7 month vs 3-cycle avg

final class CategoryComparison {
  const CategoryComparison({
    required this.categoryId,
    required this.current,
    required this.average,
    required this.deltaBp,
  });

  final String? categoryId;
  final Money current;
  final Money average;

  /// (current - average) / average in basis points; null when the average
  /// is zero.
  final int? deltaBp;
}

final class MonthVsAverage {
  const MonthVsAverage({
    required this.current,
    required this.average,
    required this.deltaBp,
    required this.cyclesCounted,
    required this.elapsedDays,
    required this.byCategory,
  });

  /// Net spend of the current period so far.
  final Money current;

  /// Mean of the earlier cycles over the same number of days.
  final Money average;
  final int? deltaBp;
  final int cyclesCounted;
  final int elapsedDays;
  final List<CategoryComparison> byCategory;
}

// ----------------------------------------------------- 8 installment timeline

final class InstallmentDue {
  const InstallmentDue({
    required this.itemId,
    required this.name,
    required this.date,
    required this.amount,
    required this.overdue,
  });

  final String itemId;
  final String name;
  final CivilDate date;
  final Money amount;

  /// The due date is before today and unpaid; shown in the first month.
  final bool overdue;
}

final class InstallmentMonth {
  const InstallmentMonth({
    required this.year,
    required this.month,
    required this.total,
    required this.dues,
  });

  final int year;
  final int month;
  final Money total;
  final List<InstallmentDue> dues;
}

// ---------------------------------------------------- 9 subscriptions x12

final class SubscriptionCost {
  const SubscriptionCost({
    required this.itemId,
    required this.name,
    required this.amount,
    required this.annual,
  });

  final String itemId;
  final String name;

  /// One charge.
  final Money amount;

  /// The cost over twelve months (BR-SUB-02).
  final Money annual;
}

final class SubscriptionsAnnual {
  const SubscriptionsAnnual({required this.items, required this.annualTotal});
  final List<SubscriptionCost> items;
  final Money annualTotal;
}

// --------------------------------------------------------- 10 cards split

final class CardSpend {
  const CardSpend({
    required this.accountId,
    required this.label,
    required this.kind,
    required this.spend,
    required this.shareBp,
    required this.count,
  });

  final String accountId;
  final String label;
  final String kind;
  final Money spend;
  final int shareBp;
  final int count;
}

// ------------------------------------------------------------ 11 net worth

/// A snapshot value in its own unit: a currency code, or a gold unit.
final class NetWorthPoint {
  const NetWorthPoint({
    required this.takenOn,
    required this.unit,
    required this.assetsMinor,
    required this.liabilitiesMinor,
  });

  final CivilDate takenOn;
  final String unit;
  final int assetsMinor;
  final int liabilitiesMinor;

  int get netMinor => assetsMinor - liabilitiesMinor;
}

// ------------------------------------------------- 12 personal inflation

final class InflationPoint {
  const InflationPoint({
    required this.year,
    required this.month,
    required this.indexBp,
    required this.merchants,
  });

  final int year;
  final int month;

  /// 10000 is the base; 10500 is +5%.
  final int indexBp;

  /// How many repeated merchants the point is based on.
  final int merchants;
}
