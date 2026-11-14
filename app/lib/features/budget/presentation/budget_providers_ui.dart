// T-101: providers for S-22 / S-23. Widgets read these; none touches the DB.

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/budgets_dao.dart';
import '../application/budget_providers.dart';
import '../application/cycle_app_wiring.dart';
import '../data/budget_mapper.dart';
import 'budget_view.dart';

/// 0 = the current cycle, -1 = the one before, and so on.
final budgetCycleOffsetProvider = NotifierProvider<BudgetCycleOffset, int>(
  BudgetCycleOffset.new,
  name: 'budgetCycleOffsetProvider',
);

class BudgetCycleOffset extends Notifier<int> {
  @override
  int build() => 0;

  void previous() => state = state - 1;
  void next() {
    if (state < 0) state = state + 1;
  }
}

/// Bumped by the editor after a save so S-22 recomputes.
final budgetEditVersionProvider = NotifierProvider<_Version, int>(
  _Version.new,
  name: 'budgetEditVersionProvider',
);

class _Version extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final categoryRowsProvider = FutureProvider<List<CategoryRow>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return (db.select(db.categories)
        ..where((c) => c.isArchived.equals(0))
        ..orderBy([(c) => OrderingTerm.asc(c.sort)]))
      .get();
});

/// Stored budgets (cycle period) of every currency.
final cycleBudgetRowsProvider = FutureProvider<List<BudgetRow>>((ref) async {
  ref.watch(budgetEditVersionProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  return (db.select(
    db.budgets,
  )..where((b) => b.period.equals(BudgetPeriod.cycle))).get();
});

final budgetScreenDataProvider = FutureProvider<BudgetScreenData>((ref) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final repo = await ref.watch(cycleRepositoryProvider.future);
  final today = ref.watch(todayProvider);
  ref.watch(cycleDataVersionProvider);
  final rows = await ref.watch(cycleBudgetRowsProvider.future);
  final cats = {
    for (final c in await ref.watch(categoryRowsProvider.future)) c.id: c,
  };
  final offset = ref.watch(budgetCycleOffsetProvider);
  var cycle = schedule.cycleOn(today);
  for (var i = 0; i < -offset; i++) {
    cycle = schedule.cycleOn(cycle.start.plusDays(-1));
  }
  final totals = await repo.totals(cycle);
  final basis = await repo.cycleBudgets();
  return buildBudgetScreenData(
    cycle: cycle,
    today: today,
    totals: totals,
    basis: basis,
    budgets: [
      for (final r in rows)
        if (r.categoryId != null)
          BudgetInput(
            spec: budgetSpecOf(r),
            nameAr: cats[r.categoryId]?.nameAr ?? r.categoryId!,
            nameEn: cats[r.categoryId]?.nameEn ?? r.categoryId!,
          ),
    ],
    calendarMonth: schedule.eras.length == 1 && schedule.currentDay == 1,
    hasPrevious: offset > -24,
  );
});
