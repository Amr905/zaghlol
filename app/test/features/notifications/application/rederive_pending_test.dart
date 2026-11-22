// FU-267: after a restart, alerts the platform still holds are cancelled and
// scheduled again with text for the current "hide amounts" setting, re-derived
// from their sources. Synthetic data only.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/fired_alerts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/notifications/application/housekeeping_providers.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';

import '../../../core/db/financial_fixtures.dart';

class _Gw implements NotificationGateway {
  final shown = <PlatformNotification>[];
  int cancels = 0;
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> cancelScheduled() async => cancels++;
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  // Local 23:30 on a Wednesday; quiet hours 22:00-07:00.
  final now = DateTime(2026, 11, 11, 23, 30);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    await AccountsDao(db).insert(account('acc1'));
    repo = SettingsRepository(SettingsDao(db));
    await repo.set(Settings.quietHoursEnabled, true);
    await repo.set(Settings.quietHoursStartMin, 22 * 60);
    await repo.set(Settings.quietHoursEndMin, 7 * 60);
  });

  tearDown(() => db.close());

  /// A fresh app process over the same database (scheduled alerts held in
  /// memory are gone).
  ProviderContainer process(_Gw gw) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith(
          (ref) async => SettingsRepository(SettingsDao(db)),
        ),
        notificationGatewayProvider.overrideWithValue(gw),
        clockProvider.overrideWithValue(() => now.toUtc()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> fire(String kind, String subject, DateTime at) =>
      FiredAlertsDao(db).markFired(
        kind: kind,
        subjectId: subject,
        periodKey: 'p',
        at: at.toUtc().millisecondsSinceEpoch,
      );

  test('hidden at start: scheduled alerts are cancelled, only the ones '
      'quiet hours were holding are released', () async {
    await repo.set(Settings.hideAmountsApp, true);
    await fire('budget', 'held', DateTime(2026, 11, 11, 23)); // quiet: held
    await fire('budget', 'shown', DateTime(2026, 11, 11, 12)); // shown at once
    final gw = _Gw();
    final c = process(gw);

    final released = await c.read(rederivePendingAlertsProvider)();

    expect(gw.cancels, 1);
    expect(released, 1);
    final dao = FiredAlertsDao(db);
    expect(
      await dao.hasFired(kind: 'budget', subjectId: 'held', periodKey: 'p'),
      isFalse,
    );
    expect(
      await dao.hasFired(kind: 'budget', subjectId: 'shown', periodKey: 'p'),
      isTrue,
    );
  });

  test('amounts shown and nothing waiting: nothing is cancelled', () async {
    await fire('budget', 'shown', DateTime(2026, 11, 11, 12));
    final gw = _Gw();
    final c = process(gw);
    expect(await c.read(rederivePendingAlertsProvider)(), 0);
    expect(gw.cancels, 0);
  });

  test('a duplicate-charge alert held by quiet hours comes back redacted '
      'after a restart with hide-amounts on', () async {
    final at = now.toUtc().millisecondsSinceEpoch;
    Future<void> expense(String id, int ms) => TransactionsDao(db).insert(
      txn(
        id,
        amountMinor: 15000,
        merchant: 'Shop',
        merchantNorm: 'shop',
        occurredAt: ms,
      ),
    );
    await expense('a', at - 5 * 60000);
    await expense('b', at - 3 * 60000);

    // Process 1: amounts shown; the alert is scheduled for 07:00 with text.
    final gw1 = _Gw();
    final c1 = process(gw1);
    await c1.read(duplicateCheckProvider)();
    expect(gw1.shown.single.at, isNotNull);
    final visible = gw1.shown.single.body;
    final id = gw1.shown.single.id;
    // The old process is gone (its in-memory state must not react).
    c1.dispose();

    // The user hides amounts; the process restarts. Memory is gone.
    await repo.set(Settings.hideAmountsApp, true);
    final gw2 = _Gw();
    final c2 = process(gw2);
    await c2.read(resumeJobsProvider)(coldStart: true);

    expect(gw2.cancels, 1);
    expect(gw2.shown, hasLength(1));
    expect(gw2.shown.single.id, id);
    expect(gw2.shown.single.at, isNotNull);
    expect(gw2.shown.single.body, isNot(visible));
    expect(gw2.shown.single.body, isNot(matches(RegExp('150|١٥٠'))));
  });

  test('switching hide-amounts off schedules the waiting alert with '
      'amounts again', () async {
    final at = now.toUtc().millisecondsSinceEpoch;
    Future<void> expense(String id, int ms) => TransactionsDao(db).insert(
      txn(
        id,
        amountMinor: 15000,
        merchant: 'Shop',
        merchantNorm: 'shop',
        occurredAt: ms,
      ),
    );
    await expense('a', at - 5 * 60000);
    await expense('b', at - 3 * 60000);
    await repo.set(Settings.hideAmountsApp, true);
    final gw1 = _Gw();
    await process(gw1).read(duplicateCheckProvider)();
    final hiddenBody = gw1.shown.single.body;

    await repo.set(Settings.hideAmountsApp, false);
    final gw2 = _Gw();
    final released = await process(gw2)
        .read(rederivePendingAlertsProvider)(rerun: true);

    expect(released, 1);
    expect(gw2.cancels, 1);
    expect(gw2.shown.single.body, isNot(hiddenBody));
    expect(gw2.shown.single.body, matches(RegExp('150|١٥٠')));
  });
}
