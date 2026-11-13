// T-095: budget progress and threshold crossing (FR-BUD-02..06, BR-BUD-02,
// EC-24). Pure. A budget counts only spend in its own currency (D-28); money
// is never converted or summed across currencies. Percentages use integer
// math only.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// A budget as the engine sees it. [categoryId] null is the overall budget.
final class BudgetSpec {
  const BudgetSpec({
    required this.id,
    required this.categoryId,
    required this.limit,
    required this.thresholds,
    this.rollover = false,
    this.annual = false,
  });

  final String id;
  final String? categoryId;
  final Money limit;

  /// Percent of the limit, ascending.
  final List<int> thresholds;
  final bool rollover;
  final bool annual;
}

final class BudgetProgress {
  const BudgetProgress({
    required this.spec,
    required this.spent,
    required this.effectiveLimit,
    required this.percent,
    required this.crossed,
  });

  final BudgetSpec spec;
  final Money spent;

  /// The limit plus any rollover carried in.
  final Money effectiveLimit;

  /// Floored whole percent; null when the limit is zero (EC-24).
  final int? percent;

  /// Thresholds reached, ascending; empty when the limit is zero.
  final List<int> crossed;

  Money get remaining => effectiveLimit - spent;
}

/// Spend of [spec] in its own currency within [totals]; zero when the
/// currency has no activity. Other currencies are ignored.
Money budgetSpent(BudgetSpec spec, Map<Currency, CycleTotals> totals) {
  final c = spec.limit.currency;
  final t = totals[c];
  if (t == null) return Money(c, 0);
  if (spec.categoryId == null) return t.spend;
  return Money(c, t.byCategoryMinor[spec.categoryId] ?? 0);
}

/// Unused part of [prev] to carry into the next cycle (FR-BUD-05); never
/// negative.
Money rolloverCarry(BudgetSpec spec, Map<Currency, CycleTotals> prevTotals) {
  final left = spec.limit - budgetSpent(spec, prevTotals);
  return left.minor > 0 ? left : Money(spec.limit.currency, 0);
}

BudgetProgress evaluateBudget(
  BudgetSpec spec,
  Map<Currency, CycleTotals> totals, {
  Money? carry,
}) {
  final spent = budgetSpent(spec, totals);
  var limit = spec.limit;
  if (spec.rollover && carry != null) {
    // `+` refuses mixed currencies.
    limit = limit + carry;
  }
  if (limit.minor <= 0) {
    return BudgetProgress(
      spec: spec,
      spent: spent,
      effectiveLimit: limit,
      percent: null,
      crossed: const [],
    );
  }
  final pct = (spent.minor * 100) ~/ limit.minor;
  return BudgetProgress(
    spec: spec,
    spent: spent,
    effectiveLimit: limit,
    percent: pct,
    crossed: [
      for (final t in spec.thresholds)
        if (pct >= t) t,
    ],
  );
}
