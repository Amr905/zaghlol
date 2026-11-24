// T-237: shared helpers of the E2E-04/05/06 device tests (real app on the
// Android emulator, devSms flavor). Prints `E2E_DEVICE <tag> ...` lines; never a
// message body or an amount outside the test's own synthetic numbers.
//
// The script (.github/scripts/e2e-device.sh) watches the test log for
// `E2E_DEVICE SEND <phase>` and then sends that phase's synthetic SMS through
// the emulator modem.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/db/app_database.dart' show AppDatabase;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

/// Strips bidi marks so shown text compares with the expected text.
String cleanBidi(String s) =>
    s.replaceAll(RegExp('[\\u2066-\\u2069\\u200e\\u200f\\u061c]'), '');

class E2e {
  E2e(this.tag, this.binding);

  final String tag;
  final IntegrationTestWidgetsFlutterBinding binding;
  final List<String> problems = [];
  bool _surfaceConverted = false;

  void say(String line) {
    // ignore: avoid_print
    print('E2E_DEVICE $tag $line');
  }

  /// Asks the script to send the SMS of [phase].
  void send(String phase) {
    // ignore: avoid_print
    print('E2E_DEVICE SEND $phase');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('MISMATCH $what');
    } else {
      say('OK $what');
    }
  }

  bool found(Finder f) {
    try {
      return f.evaluate().isNotEmpty;
    } on TypeError {
      return false;
    }
  }

  Future<void> settle(WidgetTester t, [int ms = 800]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    try {
      if (!_surfaceConverted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        _surfaceConverted = true;
      }
      await settle(t, 400);
      final bytes = await binding.takeScreenshot(name);
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/ci_screens',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      say('SHOT $name');
    } on Object catch (err) {
      say('SHOT_FAILED $name ${err.runtimeType}');
    }
  }

  Future<bool> waitUntil(
    WidgetTester t,
    Future<bool> Function() cond, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 300));
      if (await cond()) return true;
    }
    return false;
  }

  Future<void> waitFor(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
    String? what,
  }) async {
    final ok = await waitUntil(t, () async => found(f), timeout: timeout);
    if (!ok) fail('timed out waiting for ${what ?? f}');
  }

  Future<void> go(WidgetTester t, String route) async {
    rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    await settle(t, 300);
    GoRouter.of(rootNavigatorKey.currentContext!).go(route);
    await settle(t, 2000);
  }

  /// Seeds a returning English user (first-run skipped, amounts shown), then
  /// starts the real app. [seed] may write more settings before the start.
  Future<ProviderContainer> boot(
    WidgetTester t, {
    Future<void> Function(SettingsRepository settings)? seed,
  }) async {
    final now = DateTime.now();
    final dir = await resolveDbDirectory();
    final c0 = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    final s = await c0.read(settingsRepositoryProvider.future);
    await s.set(
      Settings.setupInstalledOn,
      CivilDate(now.year, now.month, now.day).epochDay,
    );
    await s.set(Settings.language, LanguagePref.en);
    await s.set(Settings.hideAmountsApp, false);
    if (seed != null) await seed(s);
    await (await c0.read(appDatabaseProvider.future)).close();
    c0.dispose();

    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.exceptionAsString();
      if (text.contains('overflowed') || text.contains('parentDataDirty')) {
        return;
      }
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    await app.main();
    await waitFor(t, find.text('Home'), what: 'Home');
    await settle(t, 1500);
    return ProviderScope.containerOf(rootNavigatorKey.currentContext!);
  }

  Future<List<Map<String, Object?>>> rows(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).get()).map((r) => r.data).toList();

  Future<int> count(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  /// Whole-month period of [d] for the chart queries.
  int monthIndex(DateTime d) => d.year * 12 + d.month - 1;
}
