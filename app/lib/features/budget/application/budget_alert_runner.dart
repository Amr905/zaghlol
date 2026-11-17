// FU-253 (FU-136): runs the budget threshold alerts for the current cycle
// and, when an annual budget exists, for the calendar year (its totals and
// its `YYYY` dedupe key). Reads only; the alert service dedupes per
// threshold per period, so running it after every ingest batch and at start
// is safe. Rollover budgets alert against limit + carry, the carry coming
// from the same function the budget screen uses (rollover_carry.dart); the
// carry comes from the closed previous cycle, so it does not move during the
// cycle and the per-threshold dedupe holds.
// Corrupt budget rows are skipped. Nothing here logs.

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../notifications/data/notification_service.dart' show AlertOutcome;
import '../data/budget_mapper.dart';
import '../data/cycle_repository.dart';
import '../domain/budget_progress.dart';
import 'budget_alert_service.dart';
import 'rollover_carry.dart';

/// The calendar year containing [today] as a [Cycle] (Jan 1 to Dec 31).
Cycle calendarYearOf(CivilDate today) => Cycle(
  start: CivilDate(today.year, 1, 1),
  end: CivilDate(today.year, 12, 31),
);

/// Returns the outcomes of the alerts raised.
Future<List<AlertOutcome>> runBudgetAlerts({
  required AppDatabase db,
  required CycleRepository cycles,
  required Cycle cycle,
  required PaydaySchedule schedule,
  required BudgetAlertService service,
}) async {
  final rows = await (db.select(
    db.budgets,
  )..orderBy([(b) => OrderingTerm.asc(b.id)])).get();
  final specs = <BudgetSpec>[];
  for (final row in rows) {
    final spec = tryBudgetSpecOf(row);
    if (spec != null) specs.add(spec);
  }
  if (specs.isEmpty) return const [];
  final totals = specs.any((s) => !s.annual)
      ? await cycles.computeLive(cycle)
      : const <Currency, CycleTotals>{};
  ({Map<Currency, CycleTotals> totals, String key})? year;
  if (specs.any((s) => s.annual)) {
    final y = calendarYearOf(cycles.today);
    year = (totals: await cycles.computeLive(y), key: '${y.start.year}');
  }
  final carries = await rolloverCarries(
    cycles: cycles,
    schedule: schedule,
    cycle: cycle,
    specs: specs,
  );
  return service.run(cycle, specs, totals, carries: carries, year: year);
}
