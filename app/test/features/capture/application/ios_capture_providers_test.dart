// T-066: the iOS composition of the capture module: the shared drain runs
// over the iOS spool port behind the pause gate, the foreground hook asks for
// the background refresh at start and on every resume, health has no Android
// issues, and the setup checker follows the 7-day silence rule.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/application/ios_setup_providers.dart';
import 'package:zaghlol/features/capture/data/ios_capture_activity.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/domain/ios_setup_checker.dart';
import 'package:zaghlol/features/capture/presentation/capture_settings_screen.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';

import '../../../ingestion/ingestion_fakes.dart';
import '../support/capture_fakes.dart';

final DateTime _now = DateTime.utc(2026, 11, 14, 12);
const int _day = 24 * 60 * 60 * 1000;

final class _Activity implements IosCaptureActivity {
  _Activity(this.last);
  final int? last;
  @override
  Stream<int?> watchLastCaptureAtMs() => Stream.value(last);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeHost host;
  late FakeSpool spool;
  late FakeScheduler sched;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    host = FakeHost();
    spool = FakeSpool([], <String>[]);
    sched = FakeScheduler();
  });
  tearDown(() async {
    CaptureEventsApi.setUp(null);
    await db.close();
  });

  ProviderContainer container({int? lastCapture, bool ios = true}) {
    final c = ProviderContainer(
      overrides: [
        dbDirectoryProvider.overrideWithValue(Directory.systemTemp),
        appDatabaseProvider.overrideWith((ref) async => db),
        captureHostPortProvider.overrideWithValue(host),
        captureSpoolPortProvider.overrideWithValue(spool),
        captureSchedulerProvider.overrideWithValue(sched),
        captureIosProvider.overrideWithValue(ios),
        captureRegistryLoaderProvider.overrideWithValue(loadSpikeRegistry),
        clockProvider.overrideWithValue(() => _now),
        iosCaptureActivityProvider.overrideWith(
          (ref) async => _Activity(lastCapture),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts on iOS: drains the spool and asks for the background refresh '
      'at start and on every resume', () async {
    spool.pending.add(entry(sid(1), channel: 'shortcut_message'));
    final c = container();
    final coordinator = (await c.read(captureCoordinatorProvider.future))!;
    await pumpEventQueue();
    expect(spool.pending, isEmpty, reason: 'Shortcuts captures drained');
    expect(host.scheduleNowCalls, 1, reason: 'starts the BG refresh chain');
    await coordinator.onResumed();
    expect(host.scheduleNowCalls, 2);
  });

  test('a failing background-refresh request never breaks the drain', () async {
    host.scheduleFails = true;
    spool.pending.add(entry(sid(1), channel: 'shortcut_message'));
    final c = container();
    await c.read(captureCoordinatorProvider.future);
    await pumpEventQueue();
    expect(spool.pending, isEmpty);
  });

  test('health on iOS: no SMS or notification issue, not degraded', () async {
    final c = container();
    await c.read(captureCoordinatorProvider.future);
    await pumpEventQueue();
    final h = c.read(captureHealthProvider);
    expect(h.mode, CaptureMode.full);
    expect(h.issues, isEmpty);
    expect(h.channels[CaptureChannel.smsLive], ChannelState.unavailable);
    expect(h.channels[CaptureChannel.notifications], ChannelState.unavailable);
  });

  test(
    'the pause gate holds the iOS drain; resuming drains what waited',
    () async {
      final c = container();
      final coordinator = (await c.read(captureCoordinatorProvider.future))!;
      await pumpEventQueue();
      final gate = c.read(ingestionPauseGateProvider);
      await gate.pause();
      spool.pending.add(entry(sid(2), channel: 'shortcut_message'));
      await coordinator.orchestrator.drainNow();
      expect(
        spool.pending,
        hasLength(1),
        reason: 'nothing stored while paused',
      );
      gate.resume();
      await pumpEventQueue();
      expect(spool.pending, isEmpty);
    },
  );

  test(
    'Android is unchanged: no refresh request, SMS issues as before',
    () async {
      final c = ProviderContainer(
        overrides: [
          dbDirectoryProvider.overrideWithValue(Directory.systemTemp),
          appDatabaseProvider.overrideWith((ref) async => db),
          captureHostPortProvider.overrideWithValue(host),
          captureSpoolPortProvider.overrideWithValue(spool),
          captureSchedulerProvider.overrideWithValue(sched),
          captureIosProvider.overrideWithValue(false),
          captureSupportedProvider.overrideWithValue(true),
          captureRegistryLoaderProvider.overrideWithValue(loadSpikeRegistry),
        ],
      );
      addTearDown(c.dispose);
      await c.read(captureCoordinatorProvider.future);
      await pumpEventQueue();
      expect(host.scheduleNowCalls, 0);
      expect(c.read(iosSetupStatusProvider), IosSetupStatus.unknown);
    },
  );

  group('setup checker provider', () {
    Future<IosSetupStatus> status(ProviderContainer c) async {
      // The status provider is what the UI watches: listen, then let the
      // activity stream deliver.
      c.listen(iosSetupStatusProvider, (_, _) {});
      await pumpEventQueue();
      return c.read(iosSetupStatusProvider);
    }

    test('a capture 2 days ago passes; 9 days ago nudges', () async {
      var c = container(lastCapture: _now.millisecondsSinceEpoch - 2 * _day);
      var s = await status(c);
      expect(s.state, IosSetupState.ok);
      expect(c.read(iosSetupCheckProvider), isTrue);
      c = container(lastCapture: _now.millisecondsSinceEpoch - 9 * _day);
      s = await status(c);
      expect(s.shouldNudge, isTrue);
      expect(s.silentDays, 9);
      expect(c.read(iosSetupCheckProvider), isFalse);
    });

    test('no capture and no first-run day: cannot tell', () async {
      final c = container();
      expect((await status(c)).state, IosSetupState.unknown);
      expect(c.read(iosSetupCheckProvider), isNull);
    });

    test('no capture: counts from the first-run day', () async {
      final c = container();
      final repo = await c.read(settingsRepositoryProvider.future);
      final today = _now.millisecondsSinceEpoch ~/ _day;
      await repo.set(Settings.setupInstalledOn, today - 10);
      await pumpEventQueue();
      expect((await status(c)).state, IosSetupState.silent);
      await repo.set(Settings.setupInstalledOn, today - 2);
      await pumpEventQueue();
      expect((await status(c)).state, IosSetupState.ok);
    });

    test('off iOS the checker is unknown', () async {
      final c = container(
        ios: false,
        lastCapture: _now.millisecondsSinceEpoch - 30 * _day,
      );
      expect(c.read(iosSetupStatusProvider), IosSetupStatus.unknown);
    });
  });
}
