// T-066: the iOS host adapter against a fake native host at the Pigeon
// channel level. Errors are code-only; Android-only calls are NOT_AVAILABLE.

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/data/capture_host_port.dart';
import 'package:zaghlol/features/capture/data/ios_capture_host_port.dart';

const String _prefix = 'dev.flutter.pigeon.zaghlol.IosCaptureHostApi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = IosCaptureHostApi.pigeonChannelCodec;
  late List<String> wire;
  String? failWith;

  setUp(() {
    wire = [];
    failWith = null;
    ByteData? answer(String name, Object? value) {
      wire.add(name);
      return failWith != null
          ? codec.encodeMessage(<Object?>[failWith, null, null])
          : codec.encodeMessage(<Object?>[value]);
    }

    messenger.setMockMessageHandler(
      '$_prefix.getSpoolStatus',
      (_) async => answer(
        'getSpoolStatus',
        SpoolStatus(
          pending: 3,
          seq: 7,
          refusedFull: 0,
          refusedGeneric: 0,
          rateLimited: 0,
          missedNotifications: 0,
          decryptDeleted: 0,
          guardState: GuardConfigState.full,
          held: 1,
        ),
      ),
    );
    messenger.setMockMessageHandler(
      '$_prefix.clearSpoolAlerts',
      (_) async => answer('clearSpoolAlerts', null),
    );
    messenger.setMockMessageHandler(
      '$_prefix.registerBackgroundRefresh',
      (_) async => answer('registerBackgroundRefresh', null),
    );
  });
  tearDown(() {
    for (final m in [
      'getSpoolStatus',
      'clearSpoolAlerts',
      'registerBackgroundRefresh',
    ]) {
      messenger.setMockMessageHandler('$_prefix.$m', null);
    }
  });

  test('status, clear and the background refresh reach the iOS host', () async {
    final port = IosCaptureHostPort();
    final s = await port.getSpoolStatus();
    expect((s.pending, s.held, s.seq), (3, 1, 7));
    await port.clearSpoolAlerts(7);
    await port.scheduleIngestionNow();
    expect(wire, [
      'getSpoolStatus',
      'clearSpoolAlerts',
      'registerBackgroundRefresh',
    ]);
  });

  test('capabilities claim nothing', () async {
    final c = await IosCaptureHostPort().getCapabilities();
    expect(c.smsGranted || c.smsFlavor || c.notificationAccess, isFalse);
  });

  test('Android-only calls are NOT_AVAILABLE and never reach native', () async {
    final port = IosCaptureHostPort();
    final calls = <Future<Object?> Function()>[
      port.requestSmsPermission,
      port.openNotificationAccessSettings,
      port.isIgnoringBatteryOptimizations,
      port.requestIgnoreBatteryOptimizations,
      () => port.writeGuardConfig(Uint8List(0)),
      () => port.queryInbox(
        InboxQuery(sinceEpochMs: 0, senderAddresses: [], pageSize: 1),
      ),
    ];
    for (final call in calls) {
      await expectLater(
        call(),
        throwsA(
          isA<CaptureHostException>().having(
            (e) => e.platformCode,
            'code',
            'NOT_AVAILABLE',
          ),
        ),
      );
    }
    expect(wire, isEmpty);
  });

  test(
    'a native error is code-only; an unknown code is PLATFORM_UNKNOWN',
    () async {
      failWith = 'IO_ERROR';
      await expectLater(
        IosCaptureHostPort().getSpoolStatus(),
        throwsA(
          isA<CaptureHostException>().having(
            (e) => e.platformCode,
            'code',
            'IO_ERROR',
          ),
        ),
      );
      failWith = 'free text with a body 123';
      await expectLater(
        IosCaptureHostPort().scheduleIngestionNow(),
        throwsA(
          isA<CaptureHostException>().having(
            (e) => e.toString().contains('body'),
            'leaks',
            false,
          ),
        ),
      );
    },
  );
}
