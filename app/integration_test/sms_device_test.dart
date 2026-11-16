// SMS-device: the SMS path on a real Android (the CI emulator): permissions
// granted with `pm grant`, synthetic SMS injected into the emulator's modem
// (`adb emu sms send`, sender ids HSBC, HSBC EG, CIB, NBE), then the REAL app
// (main(), real providers, real encrypted DB, native receiver, native Guard,
// spool, drain, ingest) must have saved them.
//
// Two phases, driven by .github/scripts/device-flows.sh:
//  1. HISTORICAL: four SMS were sent before the app's first launch (it was
//     force-stopped, so no live broadcast reached it; they sit in the inbox).
//     The test runs the same first-run inbox scan onboarding runs.
//  2. LIVE: the test prints SMS_DEVICE_READY_FOR_LIVE; the script then sends
//     the same kinds of SMS while the app is running; the native receiver
//     must pick them up.
// Synthetic data only. Prints counts and sender ids, never a message body.
//
// Run: flutter test integration_test/sms_device_test.dart --flavor devSms
//      -d <device> --no-uninstall   (the script does the adb parts)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/app/app_navigation.dart' show openSettings;
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart' show ReviewKind;
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart'
    show RawStatus;
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/settings/debug/debug_sms_diagnostics.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

const String _hsbcStale =
    'Your Credit Card ending with * 5078 has been used for USD 117.00 on '
    '08/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is EGP 110098.32';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  final problems = <String>[];

  void say(String line) {
    // ignore: avoid_print
    print('SMS_DEVICE $line');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('PROBLEM $what');
    }
  }

  Future<void> settle(WidgetTester t, [int ms = 800]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
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
      say('SHOT $name');
    } on Object catch (e) {
      say('SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  Future<int> scalar(AppDatabase db, String sql) async {
    final r = await db.customSelect(sql).getSingle();
    return r.data.values.first! as int;
  }

  // sender family -> (stored raw, saved transactions, open review items)
  Future<Map<String, List<int>>> dbCounts(AppDatabase db) async {
    final out = <String, List<int>>{};
    for (final fam in ['hsbc', 'cib', 'nbe']) {
      final like = "lower(r.sender) LIKE '$fam%'";
      out[fam] = [
        await scalar(
          db,
          "SELECT COUNT(*) FROM raw_messages r WHERE r.channel = 'sms' AND $like",
        ),
        await scalar(
          db,
          'SELECT COUNT(*) FROM transactions t JOIN raw_messages r '
          "ON r.id = t.raw_message_id WHERE r.channel = 'sms' AND $like",
        ),
        await scalar(
          db,
          'SELECT COUNT(*) FROM review_items v JOIN raw_messages r '
          'ON r.id = v.raw_message_id WHERE r.channel = \'sms\' '
          'AND v.resolved_at IS NULL AND $like',
        ),
      ];
    }
    out['all'] = [
      await scalar(db, "SELECT COUNT(*) FROM raw_messages WHERE channel='sms'"),
      await scalar(
        db,
        'SELECT COUNT(*) FROM transactions t JOIN raw_messages r '
        "ON r.id = t.raw_message_id WHERE r.channel = 'sms'",
      ),
      await scalar(
        db,
        'SELECT COUNT(*) FROM review_items v JOIN raw_messages r '
        "ON r.id = v.raw_message_id WHERE r.channel = 'sms' "
        'AND v.resolved_at IS NULL',
      ),
    ];
    return out;
  }

  void printCounts(String label, Map<String, List<int>> c) {
    for (final e in c.entries) {
      say(
        '$label ${e.key} stored=${e.value[0]} saved=${e.value[1]} '
        'review=${e.value[2]}',
      );
    }
  }

  Future<void> printNative(AppDatabase db) async {
    final s = await NativeAndDbSmsDiagnostics(db).read();
    say(
      'GUARD mode=${s.guardMode} user=${s.userState} spooled_waiting=${s.pending}',
    );
    for (final e in s.senders.entries) {
      final stages = e.value.entries
          .map((x) => '${x.key}=${x.value}')
          .join(' ');
      say('SENDER ${e.key} $stages');
    }
  }

  Future<bool> waitUntil(
    WidgetTester t,
    Future<bool> Function() cond, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 500));
      if (await cond()) return true;
    }
    return false;
  }

  testWidgets('SMS: historical inbox scan, then live receiver, then saved', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
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
    // A phone that ran an older build: one HSBC SMS sits in review, stored
    // under registry version 1. The app must read it again at start.
    final seedDb = await seed.read(appDatabaseProvider.future);
    final seedStore = DriftIngestStore(seedDb);
    final staleAt = DateTime.now().millisecondsSinceEpoch - 60000;
    await seedStore.insertRaw(
      RawInsert(
        id: 'stale0',
        channel: 'sms',
        sender: 'HSBC',
        body: _hsbcStale,
        bodyHash: bodyHashV1(
          senderKey: senderKeyOf('sms', 'HSBC'),
          body: _hsbcStale,
        ),
        receivedAtMs: staleAt,
        parseStatus: RawStatus.review,
        registryVersion: 1,
        createdAtMs: staleAt,
      ),
    );
    await seedStore.insertReview(
      id: 'rvstale0',
      kind: ReviewKind.unrecognized,
      createdAtMs: staleAt,
      rawMessageId: 'stale0',
      payload: {'reason': 'noTemplate'},
    );
    await seedDb.close();
    seed.dispose();

    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      original?.call(details);
    };

    await app.main();
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (find.text('Home').evaluate().isEmpty &&
        DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await settle(t, 1500);
    final container = ProviderScope.containerOf(
      rootNavigatorKey.currentContext!,
    );
    final db = await container.read(appDatabaseProvider.future);

    // ---- permissions and the receiver's Guard
    final caps = await container
        .read(captureHostPortProvider)
        .getCapabilities();
    say('CAPS smsFlavor=${caps.smsFlavor} smsGranted=${caps.smsGranted}');
    check(caps.smsFlavor, 'devSms build has the SMS flavour');
    check(caps.smsGranted, 'READ_SMS and RECEIVE_SMS granted by pm grant');
    await printNative(db);

    // ---- 1. HISTORICAL: the same scan onboarding runs after the permission.
    final scan = await container.read(inboxScanServiceProvider.future);
    check(scan != null, 'the inbox scan service exists');
    if (scan != null) {
      final p = await scan.startFirstRun();
      say(
        'SCAN phase=${p.phase.name} scanned=${p.scanned} '
        'imported=${p.imported} skipped=${p.skipped} '
        'institutions=${p.institutionCodes.join(",")} code=${p.code}',
      );
    }
    final historical = await waitUntil(t, () async {
      final c = await dbCounts(db);
      return c['all']![0] >= 5 && c['all']![1] >= 3;
    }, timeout: const Duration(seconds: 60));
    var c = await dbCounts(db);
    printCounts('HISTORICAL', c);
    await printNative(db);
    check(
      historical,
      'the 4 historical SMS (HSBC, HSBC EG, CIB, NBE) and the stale review row are stored',
    );
    check(
      c['hsbc']![0] == 3,
      'both historical HSBC SMS and the stale row are stored',
    );
    check(
      c['hsbc']![1] == 3,
      'both historical HSBC SMS saved, and the stale review row re-read at start',
    );
    check(c['cib']![0] == 1, 'the historical CIB SMS stored');
    check(
      c['nbe']![0] == 1 && c['nbe']![1] == 1,
      'the historical NBE SMS saved',
    );
    await shot(t, 'sms-01-home-after-scan');

    // ---- 2. LIVE: the script sends while the app runs.
    say('READY_FOR_LIVE');
    final live = await waitUntil(t, () async {
      final c2 = await dbCounts(db);
      return c2['all']![0] >= 9;
    }, timeout: const Duration(seconds: 150));
    c = await dbCounts(db);
    printCounts('FINAL', c);
    await printNative(db);
    final native = await NativeAndDbSmsDiagnostics(db).read();
    check(live, 'all 4 live SMS stored');
    check(
      c['all']![0] == 9,
      'exactly 9 SMS stored (4 historical, 4 live, 1 stale; the no-digit SMS '
      'and the personal one leave nothing)',
    );
    check(
      c['hsbc']![0] == 5 && c['hsbc']![1] == 5,
      'all 5 HSBC card SMS saved',
    );
    check(c['nbe']![0] == 2 && c['nbe']![1] == 2, 'both NBE SMS saved');
    check(
      c['cib']![0] == 2 && c['cib']![1] + c['cib']![2] >= 2,
      'both CIB SMS stored and either saved or in review',
    );
    say('REVIEW_COUNT ${c['all']![2]}');
    check(
      native.total('received') >= 5,
      'the native receiver saw the 5 live SMS (received=${native.total('received')})',
    );
    check(
      native.total('drop:no_digit') >= 1,
      'the no-digit SMS was dropped by the Guard as no_digit',
    );
    check(native.total('inbox_kept') >= 4, 'the inbox scan kept 4 SMS');
    check(native.pending == 0, 'the spool is empty at the end');
    check(native.guardMode != 'invalid', 'the native Guard base loaded');

    // ---- the diagnostics screen is reachable from Settings -> About.
    unawaited(openSettings(rootNavigatorKey.currentContext!));
    var found = false;
    for (var i = 0; i < 50 && !found; i++) {
      await t.pump(const Duration(milliseconds: 200));
      found = find.text('Settings').evaluate().isNotEmpty;
    }
    await settle(t, 800);
    Future<bool> reveal(String text) async {
      for (var i = 0; i < 12; i++) {
        if (find.text(text).evaluate().isNotEmpty) {
          await t.ensureVisible(find.text(text).first);
          await settle(t, 300);
          return true;
        }
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isEmpty) break;
        await t.drag(scrollables.first, const Offset(0, -300));
        await settle(t, 300);
      }
      return false;
    }

    if (found && await reveal('About')) {
      await t.tap(find.text('About').first);
      await settle(t, 1200);
      final row = await reveal('SMS diagnostics');
      check(row, 'About shows SMS diagnostics in the dev flavour');
      if (row) {
        await t.tap(find.text('SMS diagnostics').first);
        await settle(t, 1500);
        check(
          find.byKey(const Key('sms-diag-sender-HSBC')).evaluate().isNotEmpty,
          'the diagnostics screen lists HSBC',
        );
        await shot(t, 'sms-02-diagnostics');
      }
    } else {
      check(false, 'Settings opened with an About row');
      await shot(t, 'sms-02-settings-problem');
    }
    say('RESULT problems=${problems.length}');
    FlutterError.onError = original;
    semantics.dispose();
    expect(problems, isEmpty, reason: problems.join('; '));
  });
}
