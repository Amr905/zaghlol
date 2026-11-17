// T-095: stored budget row -> engine spec.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/budgets_dao.dart';
import '../domain/budget_progress.dart';

BudgetSpec budgetSpecOf(BudgetRow row) => BudgetSpec(
  id: row.id,
  categoryId: row.categoryId,
  limit: Money.fromStorage(row.limitMinor, row.currency),
  thresholds: budgetThresholdsOf(row),
  rollover: row.rollover != 0,
  annual: row.period == BudgetPeriod.annual,
);

/// FU-136: like [budgetSpecOf] but null for a corrupt row (unknown currency,
/// out-of-range amount, unreadable thresholds), so one bad budget never
/// stops the alert run or the screen.
BudgetSpec? tryBudgetSpecOf(BudgetRow row) {
  final limit = Money.tryFromStorage(row.limitMinor, row.currency);
  if (limit == null) return null;
  try {
    return BudgetSpec(
      id: row.id,
      categoryId: row.categoryId,
      limit: limit,
      thresholds: budgetThresholdsOf(row),
      rollover: row.rollover != 0,
      annual: row.period == BudgetPeriod.annual,
    );
  } on FormatException {
    return null;
  }
}
