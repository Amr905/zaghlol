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
