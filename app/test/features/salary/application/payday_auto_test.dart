// T-246 (D-81): the payday follows the salary. Real in-memory database; the
// ingest hook flips the setting, Undo restores and suppresses. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/budget/data/payday_schedule_store.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/salary/application/payday_auto_hook.dart';
import 'package:zaghlol/features/salary/application/payday_auto_service.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;
final int nowMs = CivilDate(2026, 11, 25).epochDay * day + 14 * 3600000;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late SettingsRepository settings;
  late PaydayAutoService service;
  var n = 0;

  Future<void> credit(
    CivilDate d, {
    String currency = 'EGP',
    String? category = 'sys:income',
    String direction = 'income',
    int internal = 0,
  }) async {
    await TransactionsDao(db).insert(
      TransactionsCompanion.insert(
        id: 'x${n++}',
        accountId: 'acc1',
        source: 'sms',
        direction: direction,
        amountMinor: 1000000,
        currency: currency,
        occurredAt: d.epochDay * day + 10 * 3600000,
        occurredTzOffsetMin: 120,
        categoryId: Value(category),
        isInternal: Value(internal),
        categorySource: 'none',
        createdAt: t0,
        updatedAt: t0,
      ),
    );
  }

  Future<int> payday() => settings.get(Settings.paydayDay);

  setUp(() async {
    n = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    await CategoriesDao(db).upsertSystem(
      code: 'income',
      nameAr: 'دخل',
      nameEn: 'Income',
      icon: 'x',
      color: '#112233',
      bucket: 'income',
      sort: 1,
    );
    settings = SettingsRepository(SettingsDao(db), nowMs: () => nowMs);
    service = PaydayAutoService(
      db,
      settings,
      PaydayScheduleStore(
        settings,
        nowUtcMs: () => nowMs,
        zone: const FixedLocalZone(120),
      ),
      nowUtcMs: () => nowMs,
    );
  });
  tearDown(() => edb.close());

  test(
    'AC: a salary ingest flips the setting and the banner shows once',
    () async {
      await credit(CivilDate(2026, 9, 24));
      await credit(CivilDate(2026, 10, 23));
      await credit(CivilDate(2026, 11, 24));
      await PaydayAutoHook(service).afterPersist(
        const PersistedTxn(txnId: 'x2', accountId: 'a', inserted: true),
      );
      expect(await payday(), 23);
      expect(await settings.get(Settings.paydayEras), isNotNull);
      final s = await settings.get(Settings.paydayAuto);
      expect(s.autoDay, 23);
      expect(s.bannerPending, isTrue);
      // A second run changes nothing (idempotent, one banner).
      expect(await service.run(), isNull);
      // Closing the banner clears it for good.
      await service.dismissBanner();
      expect((await settings.get(Settings.paydayAuto)).bannerPending, isFalse);
      expect(await service.run(), isNull);
      expect((await settings.get(Settings.paydayAuto)).bannerPending, isFalse);
    },
  );

  test(
    'AC: Undo restores the previous value and suppresses the pattern',
    () async {
      await settings.set(Settings.paydayDay, 5);
      await PaydayScheduleStore(
        settings,
        nowUtcMs: () => nowMs,
        zone: const FixedLocalZone(120),
      ).setPayday(5);
      await settings.set(Settings.paydayAuto, PaydayAutoState.empty);
      final erasBefore = await settings.get(Settings.paydayEras);
      // A hand-typed 5 is only changed when all 3 months disagree.
      await credit(CivilDate(2026, 9, 24));
      await credit(CivilDate(2026, 10, 23));
      await credit(CivilDate(2026, 11, 24));
      expect(await service.run(), 23);
      expect(await payday(), 23);
      await service.undo();
      expect(await payday(), 5);
      expect(
        (await settings.get(Settings.paydayEras))?.toJson(),
        erasBefore?.toJson(),
      );
      final s = await settings.get(Settings.paydayAuto);
      expect(s.suppressed, [23]);
      expect(s.bannerPending, isFalse);
      expect(await service.run(), isNull);
      expect(await payday(), 5);
    },
  );

  test(
    'Undo of a first-ever auto-set restores unset eras and history',
    () async {
      final old = CivilDate(2026, 8, 15);
      expect(await settings.get(Settings.paydayEras), isNull);
      final before = await settings.get(Settings.paydayDay);
      await credit(CivilDate(2026, 9, 23));
      await credit(CivilDate(2026, 10, 23));
      expect(await service.run(), 23);
      final during = (await settings.get(Settings.paydayEras))!;
      expect(during.cycleOn(old).start, CivilDate(2026, 7, 23));
      await service.undo();
      expect(await settings.get(Settings.paydayEras), isNull);
      expect(await payday(), before);
      final after = await PaydayScheduleStore(
        settings,
        nowUtcMs: () => nowMs,
        zone: const FixedLocalZone(120),
      ).load();
      expect(after.cycleOn(old).start, CivilDate(2026, 8, 1));
    },
  );

  test('typed payday that agrees with the pattern is left alone', () async {
    await PaydayScheduleStore(
      settings,
      nowUtcMs: () => nowMs,
      zone: const FixedLocalZone(120),
    ).setPayday(24);
    await credit(CivilDate(2026, 9, 24));
    await credit(CivilDate(2026, 10, 23));
    await credit(CivilDate(2026, 11, 24));
    expect(await service.run(), isNull);
    expect(await payday(), 24);
  });

  test(
    'first salary seen and never set: payday is set (day 29-31 -> 28)',
    () async {
      await credit(CivilDate(2026, 10, 31));
      expect(await service.run(), 28);
      expect(await payday(), 28);
    },
  );

  test(
    'not salary: other currency, expense, internal, other category',
    () async {
      await credit(CivilDate(2026, 11, 10), currency: 'USD');
      await credit(CivilDate(2026, 11, 11), direction: 'expense');
      await credit(CivilDate(2026, 11, 12), internal: 1);
      await credit(CivilDate(2026, 11, 13), category: null);
      expect(await service.run(), isNull);
      expect(await settings.get(Settings.paydayEras), isNull);
    },
  );

  test('a merge (not inserted) never runs the rule', () async {
    await credit(CivilDate(2026, 11, 10));
    await PaydayAutoHook(service).afterPersist(
      const PersistedTxn(txnId: 'x0', accountId: 'a', inserted: false),
    );
    expect(await settings.get(Settings.paydayEras), isNull);
  });
}
