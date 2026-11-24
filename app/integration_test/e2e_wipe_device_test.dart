// T-238 / E2E-12: Settings -> Privacy & data -> Delete everything, in the real
// app on the emulator (real encrypted database, real wipe, the in-process
// restart). Afterwards the app must be in its first-launch state: the Welcome
// screen, an empty database, settings back at their defaults and the first-run
// marker gone. .github/scripts/e2e-device.sh checks, when the test prints
// E2E12 WIPED, that the app has no posted notification or pending alarm left
// and lists the files of its private dir (names only). Synthetic data only.
//
// Run: flutter test integration_test/e2e_wipe_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_navigation.dart' show openSettings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/main.dart' as app;

import 'support/e2e_common.dart';

void main() {
  final e = E2e('E2E12');

  testWidgets('Delete everything returns the app to first launch', (t) async {
    await e.guarded(t, () async {
      await e.seedReturningUser();
      e.captureFlutterErrors();

      await app.main();
      e.say('MAIN_RETURNED');
      await e.waitFor(t, find.text('Home'), what: 'Home');
      await e.settle(t, 2000);
      await e.addTransactions([12550, 99900]);
      await e.settle(t, 800);

      Future<int> count(ProviderContainer c, String table) async {
        final db = await c.read(appDatabaseProvider.future);
        final row = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        return row.data['n']! as int;
      }

      final before = e.container();
      final txnsBefore = await count(before, 'transactions');
      e.check(txnsBefore == 2, 'two seeded transactions before the wipe');
      final repo = await before.read(settingsRepositoryProvider.future);
      e.check(
        await repo.get(Settings.language) == LanguagePref.en &&
            await repo.get(Settings.setupInstalledOn) != null,
        'the seeded settings are set before the wipe',
      );
      await e.shot(t, '01-before');

      // ---- Settings -> Privacy & data -> Delete everything.
      unawaited(openSettings(rootNavigatorKey.currentContext!));
      await e.scrollAndTap(t, find.text('Privacy & data'), 'the Privacy row');
      await e.scrollAndTap(
        t,
        find.text('Delete everything'),
        'the Delete everything row',
      );
      await e.waitFor(t, find.text('Confirmation word'), what: 'the dialog');
      await e.shot(t, '02-dialog');
      // A wrong word deletes nothing.
      await t.enterText(find.byType(TextField).last, 'nope');
      await t.tap(find.text('Delete everything').last);
      await e.settle(t, 800);
      e.check(
        e.found(find.text('Confirmation word')) &&
            await count(e.container(), 'transactions') == 2,
        'a wrong confirmation word deletes nothing',
      );
      await t.enterText(find.byType(TextField).last, 'DELETE');
      await e.settle(t, 300);
      await t.tap(find.text('Delete everything').last);

      // ---- First-launch state.
      final welcome = find.byKey(const ValueKey('welcome-start'));
      await e.waitFor(
        t,
        welcome,
        timeout: const Duration(seconds: 120),
        what: 'the Welcome screen after the wipe',
      );
      await e.settle(t, 2000);
      await e.shot(t, '03-welcome');
      final after = ProviderScope.containerOf(t.element(welcome));
      e.check(
        await count(after, 'transactions') == 0,
        'the database holds no transactions',
      );
      e.say('ACCOUNTS_AFTER ${await count(after, 'accounts')}');
      final fresh = await after.read(settingsRepositoryProvider.future);
      e.check(
        await fresh.get(Settings.setupInstalledOn) == null,
        'the first-run marker is gone',
      );
      e.check(
        await fresh.get(Settings.language) == Settings.language.defaultValue,
        'the language is back at its default',
      );
      e.check(
        await fresh.get(Settings.digits) == Settings.digits.defaultValue,
        'the digits are back at their default',
      );
      e.say('WIPED');
      await e.settle(t, 10000);
      e.finish();
    });
  });
}
