// T-063: the iOS Guard-config path over a fake native host at the Pigeon
// channel level. A sender the user always captures, built by the T-047
// writer, reaches `IosCaptureHostApi.writeGuardConfig` (the Guard the App
// Intents read) as the plaintext user part; native errors stay code-only and
// the Android-only calls never touch a channel. Synthetic senders only.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/data/capture_host_port.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show GuardUserSenderInput;

import '../support/capture_fakes.dart';

const String _prefix = 'dev.flutter.pigeon.zaghlol.IosCaptureHostApi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = IosCaptureHostApi.pigeonChannelCodec;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    for (final m in [
      'writeGuardConfig',
      'getSpoolStatus',
      'clearSpoolAlerts',
      'drainSpool',
      'ackSpool',
      'holdSpool',
      'registerBackgroundRefresh',
    ]) {
      messenger.setMockMessageHandler('$_prefix.$m', (_) async {
        calls.add(m);
        return codec.encodeMessage(<Object?>['NOT_AVAILABLE', null, null]);
      });
    }
  });

  tearDown(() {
    for (final m in [
      'writeGuardConfig',
      'getSpoolStatus',
      'clearSpoolAlerts',
      'drainSpool',
      'ackSpool',
      'holdSpool',
      'registerBackgroundRefresh',
    ]) {
      messenger.setMockMessageHandler('$_prefix.$m', null);
    }
  });

  test('a user-added sender reaches the iOS writeGuardConfig', () async {
    Uint8List? sent;
    messenger.setMockMessageHandler('$_prefix.writeGuardConfig', (data) async {
      final arg =
          (codec.decodeMessage(data)! as List<Object?>)[0]! as Uint8List;
      sent = Uint8List.fromList(arg);
      return codec.encodeMessage(<Object?>[null]);
    });
    final inputs = FakeInputs()
      ..set(
        always: const [
          GuardUserSenderInput(sender: 'MyCoop', channel: 'shortcut_message'),
        ],
      );
    final writer = GuardConfigWriter(
      host: IosCaptureHostPort(),
      inputs: inputs,
      baseRegistryVersion: 3,
      scheduler: FakeScheduler(),
    );
    final result = await writer.flush();
    expect(result.ok, isTrue);
    final json = jsonDecode(utf8.decode(sent!)) as Map<String, Object?>;
    expect(json['userSenders'], [
      {'value': 'mycoop', 'ch': 'shortcut_message'},
    ]);
    writer.dispose();
  });

  test(
    'native rejections are code-only and leave the writer not written',
    () async {
      messenger.setMockMessageHandler('$_prefix.writeGuardConfig', (_) async {
        return codec.encodeMessage(<Object?>[
          'CONFIG_INVALID',
          'ZG_CANARY_7731',
          null,
        ]);
      });
      await expectLater(
        IosCaptureHostPort().writeGuardConfig(Uint8List(1)),
        throwsA(
          isA<CaptureHostException>()
              .having((e) => e.platformCode, 'code', 'CONFIG_INVALID')
              .having((e) => '$e', 'text', isNot(contains('ZG_CANARY'))),
        ),
      );
      final writer = GuardConfigWriter(
        host: IosCaptureHostPort(),
        inputs: FakeInputs(),
        baseRegistryVersion: 3,
        scheduler: FakeScheduler(),
      );
      final result = await writer.flush();
      expect(result.status.state, GuardWriteState.rejected);
      writer.dispose();
    },
  );

  test(
    'Android-only calls answer NOT_AVAILABLE without a channel call',
    () async {
      final port = IosCaptureHostPort();
      final android = <Future<Object?> Function()>[
        port.getCapabilities,
        port.requestSmsPermission,
        port.openNotificationAccessSettings,
        port.isIgnoringBatteryOptimizations,
        port.requestIgnoreBatteryOptimizations,
        port.scheduleIngestionNow,
        () => port.queryInbox(
          InboxQuery(sinceEpochMs: 0, senderAddresses: const [], pageSize: 1),
        ),
      ];
      for (final call in android) {
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
      expect(calls, isEmpty);
    },
  );

  test('status and alerts go to the iOS host', () async {
    messenger.setMockMessageHandler('$_prefix.getSpoolStatus', (_) async {
      return codec.encodeMessage(<Object?>[
        SpoolStatus(
          pending: 2,
          seq: 7,
          refusedFull: 0,
          refusedGeneric: 0,
          rateLimited: 0,
          missedNotifications: 0,
          decryptDeleted: 0,
          guardState: GuardConfigState.full,
          held: 0,
        ),
      ]);
    });
    final status = await IosCaptureHostPort().getSpoolStatus();
    expect(status.guardState, GuardConfigState.full);
    expect(status.pending, 2);
  });
}
