// FU-253 (FU-136): budget alerts run from the database, annual budgets on
// the calendar year. Fails without the runner (nothing evaluated budgets
// outside the unit-tested service).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/budgets_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/features/budget/application/budget_alert_runner.dart';
import 'package:zaghlol/features/budget/application/budget_alert_service.dart';
import 'package:zaghlol/features/budget/application/rollover_carry.dart';
import 'package:zaghlol/features/budget/data/budget_mapper.dart';
import 'package:zaghlol/features/budget/data/cycle_cache_invalidator.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/budget/domain/budget_progress.dart';
import 'package:zaghlol/features/budget/presentation/budget_view.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');

class _Gw implements NotificationGateway {
  final shown = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

bool _on(NotificationType t) => true;

int at(int y, int m, int d) => DateTime.utc(y, m, d, 10).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late CycleRepository cycles;
  late _Gw gw;
  late Set<String> fired;
  late BudgetAlertService svc;
  final schedule = PaydaySchedule.single(25);

  Future<void> spend(String id, int minor, int when) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: 'acc1',
          direction: 'expense',
          amountMinor: minor,
          occurredAt: when,
        ).copyWith(categoryId: const Value('sys:food')),
      );

  Future<List<AlertOutcome>> run() => runBudgetAlerts(
    db: db,
    cycles: cycles,
    cycle: schedule.cycleOn(cycles.today),
    schedule: schedule,
    service: svc,
  );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1'));
    await CategoriesDao(db).upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    cycles = CycleRepository(
      db,
      nowUtcMs: () => at(2026, 11, 10),
      zone: const FixedLocalZone(120),
    );
    gw = _Gw();
    fired = {};
    Future<bool> mark({
      required String kind,
      required String subjectId,
      required String periodKey,
      required int threshold,
      required int at,
    }) async => fired.add('$kind|$subjectId|$periodKey|$threshold');
    final ns = NotificationService(
      gateway: gw,
      now: () => DateTime(2026, 11, 10, 12),
      loadPrefs: () async => const NotificationPrefs(
        typeEnabled: _on,
        quietHours: QuietHours(enabled: false, startMin: 0, endMin: 0),
        hideAmounts: false,
      ),
      markFired: mark,
      unmarkFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
      }) async {},
    );
    svc = BudgetAlertService(
      notifications: ns,
      markFired: mark,
      nowMs: () => 0,
      text: (p, t) =>
          (title: 'T$t', body: 'b', redactedTitle: 'R', redactedBody: 'r'),
    );
  });
  tearDown(() => edb.close());

  test(
    'a cycle budget over 80% alerts once; a second run is a duplicate',
    () async {
      await BudgetsDao(db).insert(
        id: 'b1',
        categoryId: 'sys:food',
        limit: Money(egp, 10000),
        period: BudgetPeriod.cycle,
        createdAt: 0,
      );
      await spend('t1', 8500, at(2026, 11, 5));
      expect(await run(), [AlertOutcome.shown]);
      expect(await run(), [AlertOutcome.duplicate]);
    },
  );

  test('an annual budget is judged on the year, not the cycle', () async {
    await BudgetsDao(db).insert(
      id: 'ann',
      categoryId: 'sys:food',
      limit: Money(egp, 100000),
      period: BudgetPeriod.annual,
      createdAt: 0,
    );
    await spend('t1', 5000, at(2026, 11, 5));
    expect(await run(), isEmpty); // 5% of the year
    await spend('t0', 80000, at(2026, 2, 3)); // outside this cycle
    expect(await run(), [AlertOutcome.shown]);
    expect(fired.single, contains('|ann|2026|'));
  });

  Future<void> rollover({int createdAt = 0}) => BudgetsDao(db).insert(
    id: 'r',
    categoryId: 'sys:food',
    limit: Money(egp, 10000),
    period: BudgetPeriod.cycle,
    rollover: true,
    createdAt: createdAt,
  );

  // The previous cycle (25 Sep - 24 Oct) left 6000 of 10000 unused.
  test('a rollover budget alerts against limit + carry', () async {
    await rollover();
    await spend('p1', 4000, at(2026, 10, 1));
    await spend('t1', 9900, at(2026, 11, 5)); // 61% of 16000: no alert
    expect(await run(), isEmpty);
    await spend('t2', 3100, at(2026, 11, 6)); // 13000/16000 = 81%
    expect(await run(), [AlertOutcome.shown]);
    expect(fired.single, endsWith('|80')); // not 100: carry applied
    expect(await run(), [AlertOutcome.duplicate]);
  });

  test(
    'a budget created this cycle carries nothing, screen or alert',
    () async {
      await rollover(createdAt: at(2026, 11, 1)); // after prev cycle started
      await spend('t1', 9900, at(2026, 11, 5));
      final cycle = schedule.cycleOn(cycles.today);
      final specs = [
        for (final r in await db.select(db.budgets).get()) budgetSpecOf(r),
      ];
      final carries = await rolloverCarries(
        cycles: cycles,
        schedule: schedule,
        cycle: cycle,
        specs: specs,
      );
      expect(carries['r'], Money(egp, 0));
      // 99% of 10000, not 61% of 16000: the 80 threshold fires.
      expect(await run(), [AlertOutcome.shown]);
      expect(fired.single, endsWith('|80'));
    },
  );

  test('the carry cut is the local day start, not UTC midnight', () async {
    // Previous cycle starts 25 Sep local (+2h) = 24 Sep 22:00 UTC. A budget
    // made at 23:00 UTC that day is 01:00 local on the 25th: inside it.
    await rollover(
      createdAt: DateTime.utc(2026, 9, 24, 23).millisecondsSinceEpoch,
    );
    final specs = [
      for (final r in await db.select(db.budgets).get()) budgetSpecOf(r),
    ];
    final carries = await rolloverCarries(
      cycles: cycles,
      schedule: schedule,
      cycle: schedule.cycleOn(cycles.today),
      specs: specs,
    );
    expect(carries['r'], Money(egp, 0));
  });

  test('a restore waiting stops the budget alerts between budgets', () async {
    for (final cat in ['sys:food', null]) {
      await BudgetsDao(db).insert(
        id: 'b-${cat ?? 'all'}',
        categoryId: cat,
        limit: Money(egp, 10000),
        period: BudgetPeriod.cycle,
        createdAt: 0,
      );
    }
    await spend('t1', 8500, at(2026, 11, 5));
    var polls = 0;
    final outcomes = await runBudgetAlerts(
      db: db,
      cycles: cycles,
      cycle: schedule.cycleOn(cycles.today),
      schedule: schedule,
      service: svc,
      shouldStop: () => polls++ > 0, // the restore arrives after one budget
    );
    expect(outcomes, hasLength(1));
  });

  test('the screen and the alert use the same effective limit', () async {
    await rollover();
    await spend('p1', 4000, at(2026, 10, 1));
    await spend('t1', 13000, at(2026, 11, 5));
    final cycle = schedule.cycleOn(cycles.today);
    final specs = [
      for (final r in await db.select(db.budgets).get()) budgetSpecOf(r),
    ];
    final carries = await rolloverCarries(
      cycles: cycles,
      schedule: schedule,
      cycle: cycle,
      specs: specs,
    );
    expect(carries['r'], Money(egp, 6000));
    final totals = await cycles.totals(cycle);
    final data = buildBudgetScreenData(
      cycle: cycle,
      today: cycles.today,
      totals: totals,
      basis: {egp: Money(egp, 10000) + basisCarry(egp, specs, carries)},
      carries: carries,
      budgets: [BudgetInput(spec: specs.single, nameAr: 'أ', nameEn: 'F')],
      calendarMonth: false,
      hasPrevious: true,
    );
    final screen = data.currencies.single;
    expect(screen.limit, Money(egp, 16000));
    final row = screen.rows.single.progress;
    expect(row.effectiveLimit, Money(egp, 16000));

    BudgetProgress? seen;
    final probe = BudgetAlertService(
      notifications: svc.notifications,
      markFired: svc.markFired,
      nowMs: () => 0,
      text: (p, t) {
        seen = p;
        return (title: 'T', body: 'b', redactedTitle: 'R', redactedBody: 'r');
      },
    );
    await runBudgetAlerts(
      db: db,
      cycles: cycles,
      cycle: cycle,
      schedule: schedule,
      service: probe,
    );
    expect(seen!.effectiveLimit, row.effectiveLimit);
    expect(seen!.percent, row.percent);
  });

  test('a changing carry never re-alerts a threshold already fired', () async {
    await rollover();
    await spend('p1', 4000, at(2026, 10, 1));
    await spend('t1', 13000, at(2026, 11, 5));
    expect(await run(), [AlertOutcome.shown]); // 81% -> 80
    expect(await run(), [AlertOutcome.duplicate]);
    // A late previous-cycle expense shrinks the carry to 2000: 108% -> 100.
    await spend('p2', 4000, at(2026, 10, 2));
    await CycleCacheInvalidator(db).invalidateAll(); // as the app wiring does
    expect(await run(), [AlertOutcome.shown]);
    expect(fired.where((k) => k.endsWith('|80')), hasLength(1));
    expect(fired.where((k) => k.endsWith('|100')), hasLength(1));
    // Carry changes again (to 0): nothing new, no storm.
    await spend('p3', 5000, at(2026, 10, 3));
    await CycleCacheInvalidator(db).invalidateAll();
    expect(await run(), [AlertOutcome.duplicate]);
    expect(await run(), [AlertOutcome.duplicate]);
    expect(fired, hasLength(2));
  });
}
