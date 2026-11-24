// T-236: SMS while the app is not running, an ignored card, and notification
// capture, end to end on the Android emulator with the REAL app (main(), real
// encrypted DB, native receiver / listener, Guard, spool, catch-up scan).
//
// One test per run, chosen by the PHASE dart-define; .github/scripts/
// killed-device.sh does the adb parts between the runs (data stays, the app is
// installed once, `--no-uninstall`):
//  prep      seeds the watermark (an older stored SMS), an ignore rule for the
//            card ending 5555 (E2E-07, through the app's own controls) and the
//            notification sender `com.android.shell` (a user sender, the
//            product's own "always capture this app" path).
//  forcestop (E2E-03) the script ran `am force-stop`, then sent a bank SMS for
//            card 4444 and one for the ignored card 5555 through the modem. A
//            force-stopped app gets no broadcast (ADR-005), so the launch
//            catch-up scan (Q7) must save the first within 10 s of its send
//            time and nothing may be stored for the second (E2E-07).
//  kill      the app process was killed (not force-stopped), then an SMS for
//            card 4444 was sent: the receiver cold-starts, spools; the app
//            must hold the transaction after launch.
//  notif     (notification capture) listener access was granted with
//            `cmd notification allow_listener`; the script posts a synthetic
//            notification from the shell package once this test prints
//            READY_FOR_NOTIF; the raw notification must be stored and, as the
//            package has no registry template, wait in review (or be saved).
// Synthetic data only. Prints ids, counts and times, never a message body.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/capture/application/user_sender_service.dart';
import 'package:zaghlol/features/capture/domain/sender_validation.dart';
import 'package:zaghlol/features/capture/presentation/capture_controls.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart'
    show RawStatus;
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/settings/debug/debug_sms_diagnostics.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

const String _phase = String.fromEnvironment('PHASE');

/// The device clock (epoch ms, whole seconds) at which the script sent.
const int _sentMs = int.fromEnvironment('SENT_MS');

// Amounts (minor units) of the synthetic messages; the script sends the same.
const int _amountKept = 73125; // EGP 731.25, card 4444 (force-stop)
const int _amountIgnored = 95375; // EGP 953.75, card 5555 (ignored)
const int _amountKilled = 84250; // EGP 842.50, card 4444 (process killed)
const int _amountNotif = 61250; // EGP 612.50 (notification)

const String _shellPackage = 'com.android.shell';

const String _watermarkBody =
    'Your Credit Card ending with * 4444 has been used for EGP 10.00 on '
    '01/11/2026 at TEST SEED. Your available limit is EGP 1000.00';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  final problems = <String>[];

  void say(String line) {
    // ignore: avoid_print
    print('KILLED_DEVICE $line');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('PROBLEM $what');
    }
  }

  bool safeFound(Finder f) {
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

  Future<int> scalar(AppDatabase db, String sql) async {
    final r = await db.customSelect(sql).getSingle();
    return (r.data.values.first as int?) ?? 0;
  }

  // Saved transactions of [source] with this amount.
  Future<int> txnCount(AppDatabase db, String source, int minor) => scalar(
    db,
    'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL '
    "AND source = '$source' AND amount_minor = $minor",
  );

  // Review items (open) of raw messages stored on [channel].
  Future<int> reviewCount(AppDatabase db, String channel) => scalar(
    db,
    'SELECT COUNT(*) FROM review_items v JOIN raw_messages r '
    "ON r.id = v.raw_message_id WHERE r.channel = '$channel' "
    'AND v.resolved_at IS NULL',
  );

  Future<void> launch(WidgetTester t) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed') || text.contains('parentDataDirty')) {
        return;
      }
      original?.call(details);
    };
    await app.main();
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!safeFound(find.text('Home')) && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await settle(t, 1500);
  }

  testWidgets('T-236 phase $_phase', (t) async {
    say('PHASE $_phase');
    if (_phase == 'prep') {
      // The watermark: an older stored SMS, so that the launch catch-up scan
      // has a point to scan from (no watermark and no request: nothing to
      // catch up, FU-085).
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
      final seedDb = await seed.read(appDatabaseProvider.future);
      final at = DateTime.now().millisecondsSinceEpoch - 120000;
      await DriftIngestStore(seedDb).insertRaw(
        RawInsert(
          id: 'wm0',
          channel: 'sms',
          sender: 'HSBC',
          body: _watermarkBody,
          bodyHash: bodyHashV1(
            senderKey: senderKeyOf('sms', 'HSBC'),
            body: _watermarkBody,
          ),
          receivedAtMs: at,
          parseStatus: RawStatus.parsed,
          registryVersion: 1,
          createdAtMs: at,
        ),
      );
      await seedDb.close();
      seed.dispose();
    }

    await launch(t);
    final container = ProviderScope.containerOf(
      rootNavigatorKey.currentContext!,
    );
    final db = await container.read(appDatabaseProvider.future);
    final launchedAt = DateTime.now();
    final caps = await container
        .read(captureHostPortProvider)
        .getCapabilities();
    say(
      'CAPS smsFlavor=${caps.smsFlavor} smsGranted=${caps.smsGranted} '
      'notificationAccess=${caps.notificationAccess}',
    );
    check(caps.smsFlavor && caps.smsGranted, 'SMS flavour with permission');
    final diag0 = await NativeAndDbSmsDiagnostics(db).read();
    say(
      'NATIVE_AT_LAUNCH spooled_waiting=${diag0.pending} '
      'received=${diag0.total('received')}',
    );
    await shot(t, 'killed-$_phase-01-home');

    switch (_phase) {
      case 'prep':
        final controls = await container.read(captureControlsProvider.future);
        final added = await controls.add(
          const IgnoreTarget(
            institutionCode: 'hsbc',
            last4: '5555',
            channel: IgnoreChannel.sms,
          ),
        );
        say('IGNORE_RULE created=${added.created} guard=${added.guard}');
        check(added.created, 'the ignore rule for card 5555 was created');
        check(
          added.guard?.ok ?? false,
          'the Guard config was written with the rule',
        );
        final sender = await UserSenderService(CaptureControlsDao(db))
            .setAlwaysCapture(
              channel: UserSenderChannel.notification,
              sender: _shellPackage,
              always: true,
            );
        say('USER_SENDER ${sender.runtimeType}');
        check(sender is UserSenderSaved, 'the notification sender was saved');
        final coordinator = await container.read(
          captureCoordinatorProvider.future,
        );
        final w = await coordinator?.onRuleChanged();
        say('GUARD_WRITE ${w?.status.state.name}');
        check(w?.ok ?? false, 'the Guard config with the sender was written');
        final native = await NativeAndDbSmsDiagnostics(db).read();
        check(native.guardMode != 'invalid', 'the native Guard base loaded');
        await shot(t, 'killed-prep-02-done');

      case 'forcestop':
        // E2E-03: the force-stopped app got no broadcast; the launch catch-up
        // must read the inbox and save the SMS.
        final seen = await waitUntil(
          t,
          () async => await txnCount(db, 'sms', _amountKept) >= 1,
          timeout: const Duration(seconds: 60),
        );
        final savedAfterLaunchMs = DateTime.now()
            .difference(launchedAt)
            .inMilliseconds;
        say('FORCESTOP saved=$seen after_launch_ms=$savedAfterLaunchMs');
        check(seen, 'E2E-03: the SMS sent while force-stopped was saved');
        if (seen) {
          final rx = await db
              .customSelect(
                'SELECT r.received_at AS at FROM raw_messages r JOIN '
                'transactions t ON t.raw_message_id = r.id '
                'WHERE t.amount_minor = $_amountKept',
              )
              .getSingle();
          final receivedAt = rx.read<int>('at');
          final delta = receivedAt - _sentMs;
          say('RECEIVED_AT_DELTA_MS $delta');
          check(
            delta >= -2000 && delta <= 10000,
            'E2E-03: received time is within 10 s of the send time '
            '(delta $delta ms)',
          );
          check(
            await txnCount(db, 'sms', _amountKept) == 1,
            'E2E-03: exactly one transaction (no duplicate)',
          );
        }
        // E2E-07: the catch-up has run (the kept one is in); the ignored
        // card's SMS must leave nothing: no transaction, no review item, no
        // stored raw message.
        final scan = await container.read(inboxScanServiceProvider.future);
        await scan?.idle;
        await settle(t, 5000);
        final ignoredTxn = await txnCount(db, 'sms', _amountIgnored);
        final ignoredRaw = await scalar(
          db,
          "SELECT COUNT(*) FROM raw_messages WHERE body LIKE '%5555%'",
        );
        final ignoredReview = await scalar(
          db,
          'SELECT COUNT(*) FROM review_items v JOIN raw_messages r '
          "ON r.id = v.raw_message_id WHERE r.body LIKE '%5555%'",
        );
        say(
          'IGNORED txn=$ignoredTxn raw=$ignoredRaw review=$ignoredReview '
          'review_open_total=${await reviewCount(db, 'sms')}',
        );
        check(ignoredTxn == 0, 'E2E-07: no transaction for the ignored card');
        check(ignoredRaw == 0, 'E2E-07: no raw message kept for the card');
        check(ignoredReview == 0, 'E2E-07: no review item for the card');
        await shot(t, 'killed-forcestop-02-home');

      case 'kill':
        final seen = await waitUntil(
          t,
          () async => await txnCount(db, 'sms', _amountKilled) >= 1,
          timeout: const Duration(seconds: 60),
        );
        final d = await NativeAndDbSmsDiagnostics(db).read();
        say(
          'KILL saved=$seen after_launch_ms='
          '${DateTime.now().difference(launchedAt).inMilliseconds} '
          'received=${d.total('received')} spooled_waiting_now=${d.pending} '
          'spooled_waiting_at_launch=${diag0.pending}',
        );
        check(seen, 'the SMS sent after the process was killed was saved');
        if (seen) {
          final rx = await db
              .customSelect(
                'SELECT r.received_at AS at FROM raw_messages r JOIN '
                'transactions t ON t.raw_message_id = r.id '
                'WHERE t.amount_minor = $_amountKilled',
              )
              .getSingle();
          final delta = rx.read<int>('at') - _sentMs;
          say('RECEIVED_AT_DELTA_MS $delta');
          check(
            delta >= -2000 && delta <= 10000,
            'received time is within 10 s of the send time (delta $delta ms)',
          );
        }
        await shot(t, 'killed-kill-02-home');

      case 'notif':
        if (!caps.notificationAccess) {
          say('NOTE notification access not reported as granted');
        }
        check(caps.notificationAccess, 'listener access was granted');
        say('READY_FOR_NOTIF');
        final stored = await waitUntil(
          t,
          () async =>
              await scalar(
                db,
                "SELECT COUNT(*) FROM raw_messages WHERE channel='notification'",
              ) >=
              1,
          timeout: const Duration(seconds: 90),
        );
        check(stored, 'the posted notification was stored as a raw message');
        final saved = await waitUntil(
          t,
          () async =>
              await txnCount(db, 'notification', _amountNotif) >= 1 ||
              await reviewCount(db, 'notification') >= 1,
          timeout: const Duration(seconds: 30),
        );
        final txns = await txnCount(db, 'notification', _amountNotif);
        final reviews = await reviewCount(db, 'notification');
        say('NOTIF stored=$stored transactions=$txns review=$reviews');
        check(saved, 'the notification became a transaction or review item');
        // A user-chosen package has no template in the registry, so the
        // notification is kept for review (new sender), not guessed at.
        check(
          reviews >= 1 || txns == 1,
          'the notification is in review or saved ($reviews, $txns)',
        );
        await shot(t, 'killed-notif-02-home');

      default:
        check(false, 'unknown PHASE');
    }
    say('RESULT problems=${problems.length}');
    expect(problems, isEmpty, reason: problems.join('; '));
  });
}
