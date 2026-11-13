// T-101: writes a validated S-23 draft. Rows keep their ids, so
// `fired_alerts` keyed by budget id survive an edit. Nothing here logs.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/budgets_dao.dart';
import '../../transactions/data/transactions_providers.dart';
import 'budget_edit_draft.dart';

typedef BudgetSaver = Future<void> Function(
  Currency currency,
  BudgetValidated v,
  bool rollover,
);

final budgetSaverProvider = FutureProvider<BudgetSaver>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final newId = ref.watch(idGeneratorProvider);
  final now = ref.watch(clockProvider);
  final dao = BudgetsDao(db);
  return (Currency currency, BudgetValidated v, bool rollover) async {
    final existing = (await dao.inCurrency(currency))
        .where((b) => b.period == BudgetPeriod.cycle)
        .toList();
    final wanted = <String?, Money>{
      if (v.total != null) null: v.total!,
      ...v.limits,
    };
    for (final row in existing) {
      final limit = wanted.remove(row.categoryId);
      if (limit == null) {
        await dao.deleteById(row.id);
        continue;
      }
      await dao.updateLimit(row.id, limit);
      await dao.setThresholds(row.id, v.thresholds);
      await (db.update(db.budgets)..where((b) => b.id.equals(row.id))).write(
        BudgetsCompanion(rollover: Value(rollover ? 1 : 0)),
      );
    }
    for (final e in wanted.entries) {
      await dao.insert(
        id: newId(),
        categoryId: e.key,
        limit: e.value,
        period: BudgetPeriod.cycle,
        rollover: rollover,
        thresholds: v.thresholds,
        createdAt: now().toUtc().millisecondsSinceEpoch,
      );
    }
  };
});
