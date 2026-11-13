// T-020: typed settings on an encrypted database. AC1 "every setting has a
// default and round-trips": the first two tests cover every key in
// [allKeys]. AC2 "no plain prefs" is the grep test at the end. Synthetic data.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../db/financial_fixtures.dart';

final Currency egp = Currency.of('EGP');
final Currency kwd = Currency.of('KWD');

/// Every key with its documented default and a non-default sample.
final List<({SettingKey<Object?> key, Object? byDefault, Object? other})>
allKeys = [
  (
    key: Settings.language,
    byDefault: LanguagePref.system,
    other: LanguagePref.ar,
  ),
  (key: Settings.digits, byDefault: DigitsPref.auto, other: DigitsPref.western),
  (key: Settings.theme, byDefault: ThemePref.system, other: ThemePref.dark),
  (key: Settings.paydayDay, byDefault: 1, other: 28),
  (
    key: Settings.paydayEras,
    byDefault: null,
    other: PaydaySchedule.single(25).withChange(CivilDate(2026, 11, 10), 1),
  ),
  (key: Settings.incomeTarget, byDefault: null, other: Money(kwd, 1234567)),
  (key: Settings.primaryCurrency, byDefault: egp, other: kwd),
  (key: Settings.approxViewEnabled, byDefault: false, other: true),
  (key: Settings.approxViewTarget, byDefault: egp, other: Currency.of('USD')),
  (key: Settings.notifBudgetThreshold, byDefault: true, other: false),
  (key: Settings.notifSpendingSpike, byDefault: true, other: false),
  (key: Settings.notifUpcomingDue, byDefault: true, other: false),
  (key: Settings.notifDuplicateCharge, byDefault: true, other: false),
  (key: Settings.notifSubscriptionRenewal, byDefault: true, other: false),
  (key: Settings.notifBackupFailure, byDefault: true, other: false),
  (key: Settings.notifWeeklySummary, byDefault: true, other: false),
  (key: Settings.quietHoursEnabled, byDefault: true, other: false),
  (key: Settings.quietHoursStartMin, byDefault: 1380, other: 0),
  (key: Settings.quietHoursEndMin, byDefault: 480, other: 1439),
  (key: Settings.appLockEnabled, byDefault: false, other: true),
  (key: Settings.appLockTimeoutS, byDefault: 60, other: 0),
  (key: Settings.hideAmountsNotifications, byDefault: false, other: true),
  (key: Settings.hideAmountsWidget, byDefault: false, other: true),
  (key: Settings.hideAmountsShareCards, byDefault: true, other: false),
  (key: Settings.captureSms, byDefault: true, other: false),
  (key: Settings.captureNotifications, byDefault: true, other: false),
  (key: Settings.contributionOptIn, byDefault: false, other: true),
  (key: Settings.scanDepthMonths, byDefault: 6, other: 24),
  (key: Settings.scanPersonalSenders, byDefault: false, other: true),
  (
    key: Settings.setupProgress,
    byDefault: <String>{},
    other: {'payday', 'lock'},
  ),
  (
    key: Settings.setupSuggestionsHandled,
    byDefault: <String>{},
    other: {'budget'},
  ),
  (key: Settings.paywallLastShown, byDefault: null, other: 1760000000000),
  (
    key: Settings.backupSchedule,
    byDefault: BackupScheduleMode.off,
    other: BackupScheduleMode.weekly,
  ),
  (
    key: Settings.backupDestination,
    byDefault: BackupDestinationPref.none,
    other: BackupDestinationPref.drive,
  ),
  (key: Settings.backupLastSuccess, byDefault: null, other: 1760000000000),
  (key: Settings.backupLastFailure, byDefault: null, other: 1760000000000),
  (key: Settings.backupReminderAt, byDefault: null, other: 1760000000000),
];

void main() {
  late EncryptedDb edb;
  late SettingsRepository repo;
  late SettingsDao dao;
  var clock = 100;

  setUp(() async {
    edb = await EncryptedDb.open();
    dao = SettingsDao(edb.db);
    clock = 100;
    repo = SettingsRepository(dao, nowMs: () => clock++);
  });

  tearDown(() => edb.close());

  test('every key is unique, valid for the table, and read as its default '
      'when unset (A-10/A-11/A-26/A-27/A-29/A-43/A-54)', () async {
    final names = allKeys.map((k) => k.key.name).toList();
    expect(names.toSet().length, names.length);
    for (final n in names) {
      expect(RegExp(r'^[a-z0-9_.]{1,64}$').hasMatch(n), isTrue);
    }
    for (final k in allKeys) {
      expect(await repo.get(k.key), k.byDefault, reason: k.key.name);
      expect(k.key.defaultValue, k.byDefault, reason: k.key.name);
    }
    expect(await dao.all(), isEmpty);
  });

  test('every key round-trips a non-default value and resets', () async {
    for (final k in allKeys) {
      await repo.set(k.key, k.other);
      expect(await repo.get(k.key), k.other, reason: k.key.name);
      await repo.reset(k.key);
      expect(await repo.get(k.key), k.byDefault, reason: k.key.name);
    }
  });

  test('every key is in the allKeys table (none forgotten)', () {
    final declared =
        File('lib/core/settings/settings_keys.dart')
            .readAsStringSync()
            .split('static final')
            .length -
        1;
    expect(allKeys.length, declared);
  });

  test('documented defaults', () async {
    expect(await repo.get(Settings.paydayDay), 1);
    expect(await repo.get(Settings.quietHoursStartMin), 23 * 60);
    expect(await repo.get(Settings.quietHoursEndMin), 8 * 60);
    expect(await repo.get(Settings.appLockTimeoutS), 60);
    expect(await repo.get(Settings.approxViewEnabled), isFalse);
    expect(await repo.get(Settings.scanDepthMonths), 6);
    expect(await repo.get(Settings.hideAmountsShareCards), isTrue);
    expect(await repo.get(Settings.incomeTarget), isNull);
  });

  test('income target keeps its currency and exponent (JPY, KWD)', () async {
    final yen = Money(Currency.of('JPY'), 5000);
    await repo.set(Settings.incomeTarget, yen);
    expect(await repo.get(Settings.incomeTarget), yen);
    final neg = Money(kwd, 1);
    await repo.set(Settings.incomeTarget, neg);
    expect((await repo.get(Settings.incomeTarget))!.currency, kwd);
    await repo.set(Settings.incomeTarget, null);
    expect(await dao.read('income_target'), isNull);
  });

  test('payday accepts 1 and 28 only within range; 0, 29-31 refused and '
      'nothing is written', () async {
    for (final bad in [0, 29, 30, 31, -1, 1000]) {
      await expectLater(
        repo.set(Settings.paydayDay, bad),
        throwsA(
          isA<SettingsException>().having(
            (e) => e.code,
            'code',
            SettingsException.invalidValue,
          ),
        ),
      );
    }
    expect(await dao.read('payday_day'), isNull);
    await repo.set(Settings.paydayDay, 1);
    await repo.set(Settings.paydayDay, 28);
    expect(await repo.get(Settings.paydayDay), 28);
  });

  test('other ranges are enforced', () async {
    for (final f in <Future<void> Function()>[
      () => repo.set(Settings.scanDepthMonths, 0),
      () => repo.set(Settings.scanDepthMonths, 25),
      () => repo.set(Settings.quietHoursStartMin, 1440),
      () => repo.set(Settings.appLockTimeoutS, -1),
      () => repo.set(Settings.setupProgress, {'Bad Slug'}),
      () => repo.set(Settings.paywallLastShown, -5),
    ]) {
      await expectLater(f(), throwsA(isA<SettingsException>()));
    }
    expect(await dao.all(), isEmpty);
  });

  test('stored garbage reads as the default and is never thrown; the '
      'refusal carries no value', () async {
    const junk = 'T020SENTINEL';
    for (final k in allKeys) {
      await dao.write(k.key.name, junk, at: 1);
      expect(await repo.get(k.key), k.byDefault, reason: k.key.name);
    }
    // Arabic-Indic digits, padding, signs and overflow are not accepted.
    for (final v in ['٥', ' 5', '+5', '05', '5.0', '99999999999999999999']) {
      await dao.write('payday_day', v, at: 1);
      expect(await repo.get(Settings.paydayDay), 1, reason: v);
    }
    await dao.write('income_target', '12:egp', at: 1);
    expect(await repo.get(Settings.incomeTarget), isNull);
    await dao.write('income_target', '1.5:EGP', at: 1);
    expect(await repo.get(Settings.incomeTarget), isNull);
    try {
      await repo.set(Settings.setupProgress, {junk});
      fail('expected a refusal');
    } on SettingsException catch (e) {
      expect(e.toString().contains(junk), isFalse);
      expect(e.code, SettingsException.invalidValue);
    }
  });

  test('set stamps updated_at from the clock; last write wins', () async {
    await repo.set(Settings.theme, ThemePref.light);
    await repo.set(Settings.theme, ThemePref.dark);
    expect(await repo.get(Settings.theme), ThemePref.dark);
    final rows = await edb.db.select(edb.db.settings).get();
    expect(rows.single.updatedAt, 101);
  });

  test(
    'watch emits the default, then each change of its own key only',
    () async {
      final seen = <int>[];
      final sub = repo.watch(Settings.paydayDay).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await repo.set(Settings.paydayDay, 15);
      await pumpEventQueue();
      await repo.set(Settings.theme, ThemePref.dark);
      await pumpEventQueue();
      await repo.reset(Settings.paydayDay);
      await pumpEventQueue();
      expect(seen, [1, 15, 1]);
    },
  );

  test('two repositories on one database: both see the last write', () async {
    final other = SettingsRepository(SettingsDao(edb.db));
    await repo.set(Settings.digits, DigitsPref.arabicIndic);
    await other.set(Settings.digits, DigitsPref.western);
    expect(await repo.get(Settings.digits), DigitsPref.western);
  });

  test('providers: default first, then the written value', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) async => edb.db)],
    );
    addTearDown(container.dispose);
    final seen = <int>[];
    container.listen(paydayDayProvider, (_, next) {
      if (next.hasValue) seen.add(next.requireValue);
    });
    await pumpEventQueue();
    final r = await container.read(settingsRepositoryProvider.future);
    await r.set(Settings.paydayDay, 9);
    for (var i = 0; i < 50 && seen.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(seen, [1, 9]);
  });

  test('no plain preferences anywhere in the app (AC2)', () {
    final banned = RegExp(
      r'shared_preferences|SharedPreferences|NSUserDefaults|UserDefaults|'
      r'PreferenceManager|getSharedPreferences|DataStore|flutter_secure_storage',
    );
    final hits = <String>[];
    for (final root in ['lib', 'ios', 'android/app/src']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final p = f.path;
        if (!RegExp(r'\.(dart|kt|java|swift|m|h|gradle|kts|xml|plist)$')
            .hasMatch(p)) {
          continue;
        }
        final code = f.readAsLinesSync().where(
          (l) => !RegExp(r'^\s*(//|\*|/\*)').hasMatch(l),
        );
        if (code.any(banned.hasMatch)) hits.add(p);
      }
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    if (banned.hasMatch(pubspec)) hits.add('pubspec.yaml');
    expect(hits, isEmpty);
  });
}
