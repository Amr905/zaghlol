// WIRE-2 (T-100): the notification service, duplicate check, weekly summary
// and backup sink wired over an in-memory database. Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/backup/application/schedule.dart';
import 'package:zaghlol/features/backup/application/schedule_providers.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';

import '../../../core/db/financial_fixtures.dart';

class _Gw implements NotificationGateway {
  final shown = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

void main() {
  late AppDatabase db;
  late _Gw gw;
  late ProviderContainer c;
  var now = DateTime.utc(2026, 11, 14, 12); // midday: outside quiet hours.

  setUp(() async {
    now = DateTime.utc(2026, 11, 14, 12);
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    await AccountsDao(db).insert(account('acc1'));
    gw = _Gw();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith(
          (ref) async => SettingsRepository(SettingsDao(db)),
        ),
        notificationGatewayProvider.overrideWithValue(gw),
        clockProvider.overrideWithValue(() => now),
        backupAlertSinkOverride,
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> expense(String id, int atMs) => TransactionsDao(db).insert(
    txn(
      id,
      amountMinor: 15000,
      merchant: 'Shop',
      merchantNorm: 'shop',
      occurredAt: atMs,
    ),
  );

  test(
    'duplicate check: two identical charges alert once, idempotently',
    () async {
      final at = now.millisecondsSinceEpoch;
      await expense('a', at - 5 * 60000);
      await expense('b', at - 3 * 60000);
      await c.read(duplicateCheckProvider)();
      await c.read(duplicateCheckProvider)();
      expect(gw.shown, hasLength(1));
      expect(gw.shown.single.payload, '/transactions/a');
    },
  );

  test('duplicate check: different amounts do not alert', () async {
    final at = now.millisecondsSinceEpoch;
    await expense('a', at - 5 * 60000);
    await TransactionsDao(db).insert(
      txn(
        'b',
        amountMinor: 9999,
        merchantNorm: 'shop',
        merchant: 'Shop',
        occurredAt: at - 3 * 60000,
      ),
    );
    await c.read(duplicateCheckProvider)();
    expect(gw.shown, isEmpty);
  });

  test('duplicate check: a switched-off type stays silent', () async {
    final at = now.millisecondsSinceEpoch;
    await expense('a', at - 5 * 60000);
    await expense('b', at - 3 * 60000);
    await SettingsRepository(SettingsDao(db))
        .set(Settings.notifDuplicateCharge, false);
    await c.read(duplicateCheckProvider)();
    expect(gw.shown, isEmpty);
  });

  test('FU-133: turning hide-amounts on re-schedules a quiet-hours alert '
      'redacted', () async {
    final repo = SettingsRepository(SettingsDao(db));
    final local = now.toLocal();
    final m = local.hour * 60 + local.minute;
    await repo.set(Settings.quietHoursEnabled, true);
    await repo.set(Settings.quietHoursStartMin, (m + 1380) % 1440);
    await repo.set(Settings.quietHoursEndMin, (m + 60) % 1440);
    final svc = await c.read(notificationServiceProvider.future);
    await svc.notify(
      const AlertRequest(
        type: NotificationType.budgetThreshold,
        subjectId: 'b1',
        periodKey: 'p1',
        title: 'Food: 4,000 EGP',
        body: 'You spent 4,000 EGP',
        redactedTitle: 'Budget alert',
        redactedBody: 'Open Zaghlol',
      ),
    );
    expect(gw.shown.single.at, isNotNull);
    await repo.set(Settings.hideAmountsNotifications, true);
    for (var i = 0; i < 20 && gw.shown.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(gw.shown, hasLength(2));
    expect(gw.shown.last.id, gw.shown.first.id);
    expect(gw.shown.last.title, 'Budget alert');
    expect(gw.shown.last.body, 'Open Zaghlol');
  });

  test('backup sink override raises the failure alert', () async {
    await c.read(backupAlertSinkProvider)(
      BackupAlertKind.failure,
      periodKey: '2026-11-14',
    );
    expect(gw.shown, hasLength(1));
    expect(gw.shown.single.payload, '/settings/backup');
  });

  test(
    'weekly summary: first run is stored, a second within 7 days skips',
    () async {
      final run = c.read(weeklySummaryRunProvider);
      expect(await run(), isTrue);
      final repo = SettingsRepository(SettingsDao(db));
      expect(
        await repo.get(Settings.notifWeeklyLastRun),
        now.millisecondsSinceEpoch,
      );
      now = now.add(const Duration(days: 6));
      expect(await run(), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await run(), isTrue);
    },
  );

  test('weekly summary: spend in the last 7 days raises one alert', () async {
    final at = now.subtract(const Duration(days: 2)).millisecondsSinceEpoch;
    await TransactionsDao(
      db,
    ).insert(txn('w1', amountMinor: 50000, merchantNorm: 'x', occurredAt: at));
    await c.read(weeklySummaryRunProvider)();
    expect(gw.shown.where((n) => n.payload == '/insights'), hasLength(1));
  });

  test(
    'FU-204d weekly summary shows a category renamed since the last run',
    () async {
      Future<void> rename(String name) => db.customStatement(
        'UPDATE categories SET name_ar = ?, name_en = ? WHERE id = ?',
        [name, name, 'sys:food'],
      );
      await CategoriesDao(db).upsertSystem(
        code: 'food',
        nameAr: 'OldName',
        nameEn: 'OldName',
        icon: 'i',
        color: '#0F7A55',
        bucket: 'needs',
        sort: 1,
      );
      Future<void> spend(String id, DateTime at) => TransactionsDao(db).insert(
        txn(
          id,
          amountMinor: 50000,
          merchantNorm: 'x',
          occurredAt: at.millisecondsSinceEpoch,
        ).copyWith(categoryId: const Value('sys:food')),
      );
      await spend('w1', now.subtract(const Duration(days: 2)));
      await c.read(weeklySummaryRunProvider)();
      expect(gw.shown.last.body, contains('OldName'));
      await rename('NewName');
      now = now.add(const Duration(days: 8));
      await spend('w2', now.subtract(const Duration(days: 1)));
      await c.read(weeklySummaryRunProvider)();
      expect(gw.shown.last.body, contains('NewName'));
    },
  );
}
