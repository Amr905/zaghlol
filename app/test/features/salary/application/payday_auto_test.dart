// T-246 (D-81): the payday follows the salary. Real in-memory database; the
// ingest hook flips the setting, Undo restores and suppresses. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
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
    // FU-296 m-2: the salary template event gives `heuristic`.
    String source = 'heuristic',
    String? merchant,
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
        categorySource: source,
        merchantRaw: Value(merchant),
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

  group('FU-296', () {
    Future<void> pattern({
      String source = 'heuristic',
      String? merchant,
    }) async {
      await credit(CivilDate(2026, 9, 24), source: source, merchant: merchant);
      await credit(CivilDate(2026, 10, 23), source: source, merchant: merchant);
      await credit(CivilDate(2026, 11, 24), source: source, merchant: merchant);
    }

    test(
      'm-2: income the user filed under Income (a gift) is no salary',
      () async {
        await pattern(source: 'user');
        expect(await service.run(), isNull);
        expect(await settings.get(Settings.paydayEras), isNull);
      },
    );

    test('m-2: a user rule, a salary word or a tied entry counts', () async {
      await pattern(source: 'user_rule');
      expect(await service.run(), 23);
    });

    test(
      'm-2: a salary word in the text counts for a user-filed credit',
      () async {
        await pattern(source: 'user', merchant: 'ACME Salary');
        expect(await service.run(), 23);
      },
    );

    test('m-2: a credit tied in salary.state counts', () async {
      await pattern(source: 'user');
      await settings.set(
        Settings.salaryState,
        SalaryState(
          entries: [
            for (final i in [0, 1, 2])
              SalaryEntry(
                txnId: 'x$i',
                captured: true,
                anchor: CivilDate(2026, 9 + i, 24),
              ),
          ],
        ),
      );
      expect(await service.run(), 23);
    });

    test('FU-308: manual rows on the expected date do not move it', () async {
      await pattern(source: 'user');
      await settings.set(
        Settings.salaryState,
        SalaryState(
          entries: [
            for (final i in [0, 1, 2])
              SalaryEntry(
                txnId: 'x$i',
                captured: false,
                anchor: CivilDate(2026, 9 + i, 24),
              ),
          ],
        ),
      );
      expect(await service.run(), isNull);
      expect(await settings.get(Settings.paydayEras), isNull);
    });

    test('m-1: only a stored salary credit runs the rule', () async {
      await pattern();
      await credit(CivilDate(2026, 11, 20), direction: 'expense');
      await credit(CivilDate(2026, 11, 21), source: 'user'); // x4: a gift
      final hook = PaydayAutoHook(service);
      for (final id in ['x3', 'x4', 'nope', '']) {
        await hook.afterPersist(
          PersistedTxn(txnId: id, accountId: 'a', inserted: true),
        );
      }
      expect(await settings.get(Settings.paydayEras), isNull);
      await hook.afterPersist(
        const PersistedTxn(txnId: 'x2', accountId: 'a', inserted: true),
      );
      expect(await payday(), 23);
    });

    test(
      'm-4: a failure writing the memory leaves the payday untouched',
      () async {
        await pattern();
        final failing = PaydayAutoService(
          db,
          _FailingSettings(SettingsDao(db), nowMs: () => nowMs),
          PaydayScheduleStore(
            settings,
            nowUtcMs: () => nowMs,
            zone: const FixedLocalZone(120),
          ),
          nowUtcMs: () => nowMs,
        );
        await expectLater(failing.run(), throwsA(isA<StateError>()));
        expect(await settings.get(Settings.paydayEras), isNull);
        expect((await settings.get(Settings.paydayAuto)).autoDay, isNull);
        // Retrying with a working store applies it with banner and Undo.
        expect(await service.run(), 23);
        expect((await settings.get(Settings.paydayAuto)).bannerPending, isTrue);
      },
    );

    test(
      'm-6: the memory keeps the real salary day behind a capped payday',
      () async {
        await credit(CivilDate(2026, 8, 31));
        await credit(CivilDate(2026, 10, 30));
        await credit(CivilDate(2026, 11, 30));
        expect(await service.run(), 28);
        final s = await settings.get(Settings.paydayAuto);
        expect(s.autoDay, 28);
        expect(s.salaryDay, 30);
      },
    );

    test('m-3: 28 / 30 / 1 month-end shifts agree end to end', () async {
      await credit(CivilDate(2026, 8, 28));
      await credit(CivilDate(2026, 9, 30));
      await credit(CivilDate(2026, 11, 1));
      expect(await service.run(), 28);
    });
  });
}

class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.dao, {super.nowMs});

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    if (key.name == Settings.paydayAuto.name) throw StateError('disk full');
    return super.set(key, value);
  }
}
