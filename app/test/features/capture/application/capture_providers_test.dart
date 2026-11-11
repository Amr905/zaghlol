// T-047: the composition. The UI engine's coordinator starts once the
// database is open (the gate), on Android with a registry only; the
// CaptureEventsApi handler is installed (Pigeon codec); resume reaches the
// coordinator through the lifecycle widget; health is a provider.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/presentation/capture_lifecycle.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';

import '../../../ingestion/ingestion_fakes.dart';
import '../support/capture_fakes.dart';

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

  ProviderContainer container({bool supported = true, bool registry = true}) {
    final c = ProviderContainer(
      overrides: [
        dbDirectoryProvider.overrideWithValue(Directory.systemTemp),
        appDatabaseProvider.overrideWith((ref) async => db),
        captureHostPortProvider.overrideWithValue(host),
        captureSpoolPortProvider.overrideWithValue(spool),
        captureSchedulerProvider.overrideWithValue(sched),
        captureSupportedProvider.overrideWithValue(supported),
        if (registry)
          captureRegistryLoaderProvider.overrideWithValue(loadSpikeRegistry),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts after the database opened: writes the config, installs the '
      'events handler, health is derived', () async {
    final c = container();
    final coordinator = await c.read(captureCoordinatorProvider.future);
    expect(coordinator, isNotNull);
    await pumpEventQueue();
    expect(host.writes, 1);
    expect(c.read(captureHealthProvider).mode, CaptureMode.full);

    // Native -> Dart over the real codec: onSpoolChanged drains (after the
    // 250 ms coalesce) in every build, not only devSms.
    spool.pending.add(entry(sid(1)));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      'dev.flutter.pigeon.zaghlol.CaptureEventsApi.onSpoolChanged',
      CaptureEventsApi.pigeonChannelCodec.encodeMessage(<Object?>[1]),
      (_) {},
    );
    expect(sched.liveDelays, contains(const Duration(milliseconds: 250)));
    sched.fire(const Duration(milliseconds: 250));
    await pumpEventQueue();
    expect(coordinator!.orchestrator.lastResult?.code, isNull);
    expect(spool.pending, isEmpty, reason: 'drained on the event');
  });

  test('a permission event reaches the health provider', () async {
    final c = container();
    await c.read(captureCoordinatorProvider.future);
    await pumpEventQueue();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      'dev.flutter.pigeon.zaghlol.CaptureEventsApi.onPermissionChanged',
      CaptureEventsApi.pigeonChannelCodec.encodeMessage(<Object?>[
        CaptureCapabilities(
          smsGranted: false,
          smsFlavor: true,
          notificationAccess: true,
          postNotifications: true,
          sdkInt: 34,
        ),
      ]),
      (_) {},
    );
    await pumpEventQueue();
    expect(c.read(captureHealthProvider).mode, CaptureMode.degraded);
  });

  test('no capture off Android or without a registry (no retry storm, '
      'FU-108 L-2)', () async {
    var c = container(supported: false);
    expect(await c.read(captureCoordinatorProvider.future), isNull);
    c = container(registry: false);
    expect(await c.read(captureCoordinatorProvider.future), isNull);
    expect(host.writes, 0);
    expect(c.read(captureHealthProvider), CaptureHealth.initial);
  });

  testWidgets('resume goes to the coordinator', (tester) async {
    final c = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const CaptureLifecycle(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.runAsync(() => pumpEventQueue());
    final statusesBefore = host.log.where((l) => l == 'status').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => pumpEventQueue());
    expect(
      host.log.where((l) => l == 'status').length,
      greaterThan(statusesBefore),
    );
  });
}
