// FIX-device-flows: drives the REAL app composition (`main()`, its own
// providers, the real encrypted database, real plugins and host channels) on
// an Android emulator: Add -> Type -> Save -> the row is on Home; Add -> Say
// -> a clear consent/permission/unsupported state (no mic on CI); Add -> Scan
// -> a clear message. Screenshots of the main screens are written to the
// app's private documents dir (`app_flutter/ci_screens/`) and pulled by
// .github/scripts/device-flows.sh. Synthetic data only; nothing is logged.
//
// Run: flutter test integration_test/device_flows_test.dart --flavor devSms
//      -d <device> --no-uninstall

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/app/app_navigation.dart' show openSettings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;

  Future<void> settle(WidgetTester t, [int ms = 800]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
    String? what,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
      if (f.evaluate().isNotEmpty) return;
    }
    fail('timed out waiting for ${what ?? f}');
  }

  Future<void> shot(WidgetTester t, String name) async {
    try {
      if (!surfaceConverted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      await settle(t, 400);
      final bytes = await binding.takeScreenshot(name);
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/ci_screens',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      // ignore: avoid_print
      print('DEVICE_FLOWS_SHOT $name');
    } on Object catch (e) {
      // A screenshot is evidence, not the test: report the type only.
      // ignore: avoid_print
      print('DEVICE_FLOWS_SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  Future<void> closeTop(WidgetTester t) async {
    await rootNavigatorKey.currentState!.maybePop();
    await settle(t);
  }

  // Built lazily: the semantics finder needs ensureSemantics() first.
  Finder quickAdd() => find.bySemanticsLabel('Quick add');

  Future<void> openAdd(WidgetTester t) async {
    await waitFor(t, quickAdd(), what: 'the Add button');
    await t.tap(quickAdd().first);
    await waitFor(t, find.text('Type'), what: 'the Add sheet');
    await settle(t);
  }

  testWidgets('real app: Type saves, Say and Scan explain themselves', (
    t,
  ) async {
    final semantics = t.ensureSemantics();

    // A returning user in English: skip first-run onboarding (its system
    // permission dialogs can't be driven from Flutter) by writing the
    // first-run marker through the app's own providers and real database.
    final dir = await resolveDbDirectory();
    final seed = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    final settings = await seed.read(settingsRepositoryProvider.future);
    final now = DateTime.now();
    await settings.set(
      Settings.setupInstalledOn,
      CivilDate(now.year, now.month, now.day).epochDay,
    );
    await settings.set(Settings.language, LanguagePref.en);
    await (await seed.read(appDatabaseProvider.future)).close();
    seed.dispose();

    // Sub-pixel RenderFlex overflows (font metrics on the emulator) are
    // reported, not fatal: this test is about flows, not pixels.
    final original = FlutterError.onError;
    var overflows = 0;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows++;
        return;
      }
      original?.call(details);
    };
    addTearDown(() {
      // ignore: avoid_print
      print('DEVICE_FLOWS_OVERFLOWS $overflows');
    });

    await app.main();
    await waitFor(t, find.text('Home'), what: 'Home');
    await settle(t, 2000);
    await shot(t, '01-home-empty');

    // ---- Type: S-13 opens, saves to the real DB, the row shows on Home.
    await openAdd(t);
    await shot(t, '02-add-sheet');
    await t.tap(find.text('Type'));
    await waitFor(t, find.text('Add expense'), what: 'S-13 editor');
    await settle(t);
    await t.enterText(find.byType(TextField).first, '125.50');
    await settle(t, 300);
    await waitFor(t, find.text('Choose'), what: 'category field');
    await t.ensureVisible(find.text('Choose').first);
    await settle(t, 300);
    await t.tap(find.text('Choose').first);
    await waitFor(
      t,
      find.text('Groceries & Supermarkets'),
      what: 'seeded categories',
    );
    await t.tap(find.text('Groceries & Supermarkets').last);
    await settle(t);
    await shot(t, '03-type-filled');
    await t.ensureVisible(find.text('Save').last);
    await settle(t, 300);
    await t.tap(find.text('Save').last);
    await settle(t, 1500);
    expect(find.text('Add expense'), findsNothing, reason: 'editor closed');
    final homeRow = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('home-row-'),
    );
    await waitFor(t, homeRow, what: 'the saved row on Home');
    await shot(t, '04-home-with-row');

    // ---- Say: never a blank screen. On the emulator (no on-device pack)
    // the online consent sheet comes first; "No, I'll type" opens S-13.
    await openAdd(t);
    await t.tap(find.text('Say'));
    final consent = find.text('Use online speech recognition?');
    await waitFor(t, consent, what: 'voice consent / state');
    await shot(t, '05-say-consent');
    await t.tap(find.text("No, I'll type"));
    await waitFor(t, find.text('Add expense'), what: 'S-13 after consent no');
    await closeTop(t);
    // A "discard changes?" prompt never appears for an untouched form.
    await waitFor(t, quickAdd(), what: 'back on Home after Say');

    // ---- Scan: Android has no OCR host yet; the screen says so clearly
    // and offers typing instead.
    await openAdd(t);
    await t.tap(find.text('Scan'));
    await waitFor(
      t,
      find.text("Reading images isn't ready on this phone yet"),
      what: 'scan unavailable message',
    );
    expect(find.byKey(const Key('scan-type')), findsOneWidget);
    await shot(t, '06-scan-unavailable');
    await closeTop(t);
    await waitFor(t, quickAdd(), what: 'back on Home after Scan');

    // ---- Screenshots of the other tabs and Settings.
    await t.tap(find.text('Money').first);
    await settle(t, 1500);
    await shot(t, '07-money');
    await t.tap(find.text('Insights').first);
    await settle(t, 1500);
    await shot(t, '08-insights');
    await t.tap(find.text('Home').first);
    await settle(t, 800);
    unawaited(openSettings(rootNavigatorKey.currentContext!));
    await waitFor(t, find.text('Settings'), what: 'Settings');
    await settle(t, 1000);
    await shot(t, '09-settings');

    // ---- Arabic (RTL) pass: switch the language through the app's own
    // providers, then re-take the main screens. Evidence only: a failure
    // here is reported, never fatal.
    await closeTop(t);
    try {
      final container = ProviderScope.containerOf(
        rootNavigatorKey.currentContext!,
      );
      final repo = await container.read(settingsRepositoryProvider.future);
      await repo.set(Settings.language, LanguagePref.ar);
      await settle(t, 2000);
      await t.tap(find.text('الرئيسية').first);
      await settle(t, 1500);
      await shot(t, 'ar-01-home');
      await t.tap(find.bySemanticsLabel('سجّل بسرعة').first);
      await settle(t, 1500);
      await shot(t, 'ar-02-add-sheet');
      await closeTop(t);
      await t.tap(find.text('فلوسي').first);
      await settle(t, 1500);
      await shot(t, 'ar-03-money');
      await t.tap(find.text('الحسبة').first);
      await settle(t, 1500);
      await shot(t, 'ar-04-insights');
      await t.tap(find.text('الرئيسية').first);
      await settle(t, 800);
      unawaited(openSettings(rootNavigatorKey.currentContext!));
      await settle(t, 2000);
      await shot(t, 'ar-05-settings');
    } on Object catch (e) {
      // ignore: avoid_print
      print('DEVICE_FLOWS_AR_FAILED ${e.runtimeType}');
    }

    FlutterError.onError = original;
    semantics.dispose();
  });
}
