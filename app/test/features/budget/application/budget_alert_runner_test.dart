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
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
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

  test('a rollover budget is skipped (no carry computed here)', () async {
    await BudgetsDao(db).insert(
      id: 'r',
      categoryId: 'sys:food',
      limit: Money(egp, 10000),
      period: BudgetPeriod.cycle,
      rollover: true,
      createdAt: 0,
    );
    await spend('t1', 9900, at(2026, 11, 5));
    expect(await run(), isEmpty);
  });
}
