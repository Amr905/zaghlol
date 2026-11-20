// T-195 AC3: the salary nudge shows once per payday, follows the
// notification settings, and never comes when the salary is tied or skipped.
// Synthetic text only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_routes.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol/features/salary/application/notify_salary_check.dart';
import 'package:zaghlol/features/salary/application/salary_matching.dart';
import 'package:zaghlol/features/salary/application/salary_service.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;
final CivilDate payday = CivilDate(2026, 11, 25);

class _Gateway implements NotificationGateway {
  final shown = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late SalaryMatching matching;
  late SalaryService service;
  late _Gateway gw;
  late NotificationService notifications;
  var typeOn = true;

  AlertRequest text(AlertRequest b) => AlertRequest(
    type: b.type,
    subjectId: b.subjectId,
    periodKey: b.periodKey,
    title: 'Did it arrive?',
    body: 'Open Home',
    redactedTitle: 'Did it arrive?',
    redactedBody: 'Open Home',
    payload: b.payload,
  );

  Future<bool> run(CivilDate today) => runSalaryCheck(
    matching: matching,
    service: service,
    notifications: notifications,
    today: today,
    buildText: text,
  );

  setUp(() async {
    typeOn = true;
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    matching = SalaryMatching(
      db,
      loadSchedule: () async => PaydaySchedule.single(25),
    );
    service = SalaryService(
      db,
      DriftTransactionRepository(TransactionsDao(db)),
      zone: const FixedLocalZone(120),
    );
    await service.setPlan(
      SalaryPlan.tryCreate(amount: Money(Currency.of('EGP'), 1000000), day: 25),
    );
    gw = _Gateway();
    final fired = <String>{};
    notifications = NotificationService(
      gateway: gw,
      loadPrefs: () async => NotificationPrefs(
        typeEnabled: (t) => t != NotificationType.upcomingDue || typeOn,
        quietHours: const QuietHours(enabled: false, startMin: 0, endMin: 0),
        hideAmounts: false,
      ),
      markFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
        required at,
      }) async => fired.add('$kind|$subjectId|$periodKey|$threshold'),
      unmarkFired:
          ({
            required kind,
            required subjectId,
            required periodKey,
            required threshold,
          }) async {
            fired.remove('$kind|$subjectId|$periodKey|$threshold');
          },
      now: () => DateTime.utc(2026, 12, 1, 12),
    );
  });
  tearDown(() => edb.close());

  test('nothing during the window; one nudge after it; a second run is '
      'silent; it carries no amount and opens Home', () async {
    expect(await run(payday.plusDays(5)), isFalse);
    expect(gw.shown, isEmpty);
    expect(await run(payday.plusDays(6)), isTrue);
    expect(await run(payday.plusDays(6)), isFalse);
    expect(await run(payday.plusDays(7)), isFalse);
    expect(gw.shown, hasLength(1));
    expect(gw.shown.single.payload, '/home');
    expect(notificationTargetFor('/home'), isA<HomeTarget>());
    expect(gw.shown.single.title, isNot(contains('10')));
  });

  test('the next payday gets its own nudge', () async {
    expect(await run(payday.plusDays(6)), isTrue);
    final next = CivilDate(2026, 12, 25);
    expect(await run(next.plusDays(6)), isTrue);
    expect(gw.shown, hasLength(2));
  });

  test('no nudge when the salary was received in the window, even if the '
      'credit arrived before the plan knew (reconcile runs first)', () async {
    await TransactionsDao(db).insert(
      TransactionsCompanion.insert(
        id: 's1',
        accountId: 'acc1',
        source: 'sms',
        direction: 'income',
        amountMinor: 1000000,
        currency: 'EGP',
        occurredAt: payday.epochDay * day + 10 * 3600000,
        occurredTzOffsetMin: 120,
        categorySource: 'none',
        createdAt: t0,
        updatedAt: t0,
        merchantRaw: const Value(null),
      ),
    );
    expect(await run(payday.plusDays(6)), isFalse);
    expect(gw.shown, isEmpty);
  });

  test('skipped or recorded: no nudge', () async {
    await service.skip(payday);
    expect(await run(payday.plusDays(6)), isFalse);
  });

  test('the due-date toggle off: nothing is shown', () async {
    typeOn = false;
    expect(await run(payday.plusDays(6)), isFalse);
    expect(gw.shown, isEmpty);
  });

  test('no plan: no nudge', () async {
    await service.setPlan(null);
    expect(await run(payday.plusDays(6)), isFalse);
  });
}
