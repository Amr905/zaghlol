import '../money/money.dart';
import '../money/rounding.dart';
import 'civil_date.dart';
import 'payday_schedule.dart';

/// The budget basis of one currency: the overall cycle budget, else the sum
/// of the category cycle budgets (A-16). Null when there is none. All
/// amounts must be in one currency.
Money? budgetBasis(Money? overall, Iterable<Money> categoryBudgets) {
  if (overall != null) return overall;
  Money? sum;
  for (final b in categoryBudgets) {
    sum = sum == null ? b : sum + b;
  }
  return sum;
}

/// Safe to spend per remaining day, in minor units of the budget's currency,
/// rounded down. Null when [budget] is null or zero (EC-24); zero when
/// overspent. [spend] is the net cycle spend in the same currency.
Money? safeToSpend({
  required Money? budget,
  required Money spend,
  required Cycle cycle,
  required CivilDate today,
}) {
  if (budget == null || budget.minor == 0) return null;
  final left = budget - spend;
  final remaining = left.minor < 0 ? Money.zero(budget.currency) : left;
  return remaining.mulDiv(1, cycle.daysRemaining(today), MoneyRounding.floor);
}

/// `floor(budget × d ÷ length)` for `d` in 0..length.
Money idealBurn(Money budget, int d, int cycleLength) {
  if (cycleLength < 1 || d < 0 || d > cycleLength) {
    throw RangeError('day out of the cycle');
  }
  return budget.mulDiv(d, cycleLength, MoneyRounding.floor);
}

/// "Under the ideal line" (BR-MAS-02): spend <= the ideal burn of today.
bool isUnderIdealLine({
  required Money budget,
  required Money spend,
  required Cycle cycle,
  required CivilDate today,
}) {
  final d = cycle.dayNumber(today).clamp(0, cycle.length);
  return spend <= idealBurn(budget, d, cycle.length);
}

final class BurnPoint {
  const BurnPoint(this.day, this.ideal, this.actual);

  /// 0 (origin) .. cycle length.
  final int day;
  final Money ideal;

  /// Cumulative net spend; null after today.
  final Money? actual;
}

/// The burn chart series (design note §4). [spendByDay]: net spend minor per
/// 1-based day (see `netSpendByDay`).
List<BurnPoint> burnLine({
  required Money budget,
  required Cycle cycle,
  required CivilDate today,
  required Map<int, int> spendByDay,
}) {
  final todayN = cycle.dayNumber(today);
  var cum = Money.zero(budget.currency);
  final out = <BurnPoint>[];
  for (var d = 0; d <= cycle.length; d++) {
    if (d > 0) cum = cum + Money(budget.currency, spendByDay[d] ?? 0);
    out.add(
      BurnPoint(
        d,
        idealBurn(budget, d, cycle.length),
        d <= todayN ? cum : null,
      ),
    );
  }
  return out;
}
