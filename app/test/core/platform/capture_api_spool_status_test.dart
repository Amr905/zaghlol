// T-039: the contract additions of platform-channels.md section 2 over a
// fake native host at the Pigeon channel level (the generated codec):
// writeGuardConfig(userConfigJson) sends the plaintext bytes unchanged,
// getSpoolStatus decodes every field (nullable times, the Guard state enum),
// clearSpoolAlerts sends the seq, and native errors stay code-only.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';

const String _prefix = 'dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = AndroidCaptureHostApi.pigeonChannelCodec;

  tearDown(() {
    for (final m in [
      'writeGuardConfig',
      'getSpoolStatus',
      'clearSpoolAlerts',
      'holdSpool',
    ]) {
      messenger.setMockMessageHandler('$_prefix.$m', null);
    }
  });

  test('writeGuardConfig sends the plaintext user part as bytes', () async {
    Object? sent;
    messenger.setMockMessageHandler('$_prefix.writeGuardConfig', (data) async {
      sent = (codec.decodeMessage(data)! as List<Object?>)[0];
      return codec.encodeMessage(<Object?>[null]);
    });
    final json = Uint8List.fromList('{"v":1,"rules":[]}'.codeUnits);
    await AndroidCaptureHostApi().writeGuardConfig(json);
    expect(sent, isA<Uint8List>());
    expect(sent, json);
  });

  test('writeGuardConfig rejections arrive as code-only errors', () async {
    messenger.setMockMessageHandler('$_prefix.writeGuardConfig', (_) async {
      return codec.encodeMessage(<Object?>['CONFIG_INVALID', null, null]);
    });
    await expectLater(
      AndroidCaptureHostApi().writeGuardConfig(Uint8List(1)),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'CONFIG_INVALID')
            .having((e) => e.message, 'message', isNull)
            .having((e) => e.details, 'details', isNull),
      ),
    );
  });

  test('getSpoolStatus decodes every field', () async {
    messenger.setMockMessageHandler('$_prefix.getSpoolStatus', (_) async {
      return codec.encodeMessage(<Object?>[
        SpoolStatus(
          pending: 3,
          seq: 4294967295,
          refusedFull: 1,
          refusedGeneric: 2,
          rateLimited: 3,
          missedNotifications: 4,
          firstMissedSmsAtMs: 1731300000000,
          decryptDeleted: 5,
          keyInvalidatedAtMs: 1731300000123,
          guardState: GuardConfigState.userUnreadable,
          held: 6,
        ),
      ]);
    });
    final s = await AndroidCaptureHostApi().getSpoolStatus();
    expect(s.pending, 3);
    expect(s.seq, 4294967295);
    expect(
      [s.refusedFull, s.refusedGeneric, s.rateLimited, s.missedNotifications],
      [1, 2, 3, 4],
    );
    expect(s.firstMissedSmsAtMs, 1731300000000);
    expect(s.decryptDeleted, 5);
    expect(s.keyInvalidatedAtMs, 1731300000123);
    expect(s.guardState, GuardConfigState.userUnreadable);
    expect(s.held, 6);
  });

  test('getSpoolStatus with no alerts has null times', () async {
    messenger.setMockMessageHandler('$_prefix.getSpoolStatus', (_) async {
      return codec.encodeMessage(<Object?>[
        SpoolStatus(
          pending: 0,
          seq: 0,
          refusedFull: 0,
          refusedGeneric: 0,
          rateLimited: 0,
          missedNotifications: 0,
          decryptDeleted: 0,
          guardState: GuardConfigState.unknown,
          held: 0,
        ),
      ]);
    });
    final s = await AndroidCaptureHostApi().getSpoolStatus();
    expect(s.firstMissedSmsAtMs, isNull);
    expect(s.keyInvalidatedAtMs, isNull);
    expect(s.guardState, GuardConfigState.unknown);
  });

  test('clearSpoolAlerts sends the seq; IO_ERROR stays code-only', () async {
    final seqs = <Object?>[];
    messenger.setMockMessageHandler('$_prefix.clearSpoolAlerts', (data) async {
      seqs.add((codec.decodeMessage(data)! as List<Object?>)[0]);
      return codec.encodeMessage(<Object?>[null]);
    });
    await AndroidCaptureHostApi().clearSpoolAlerts(41);
    expect(seqs, [41]);

    messenger.setMockMessageHandler('$_prefix.clearSpoolAlerts', (_) async {
      return codec.encodeMessage(<Object?>['IO_ERROR', null, null]);
    });
    await expectLater(
      AndroidCaptureHostApi().clearSpoolAlerts(41),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'IO_ERROR')
            .having((e) => e.message, 'message', isNull),
      ),
    );
  });

  test('holdSpool sends the ids; IO_ERROR stays code-only (T-041)', () async {
    final sent = <Object?>[];
    messenger.setMockMessageHandler('$_prefix.holdSpool', (data) async {
      sent.add((codec.decodeMessage(data)! as List<Object?>)[0]);
      return codec.encodeMessage(<Object?>[null]);
    });
    await AndroidCaptureHostApi().holdSpool(['01ARZ3NDEKTSV4RRFFQ69G5FAV']);
    expect(sent, [
      ['01ARZ3NDEKTSV4RRFFQ69G5FAV'],
    ]);
    messenger.setMockMessageHandler('$_prefix.holdSpool', (_) async {
      return codec.encodeMessage(<Object?>['IO_ERROR', null, null]);
    });
    await expectLater(
      AndroidCaptureHostApi().holdSpool(const []),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'IO_ERROR')
            .having((e) => e.message, 'message', isNull),
      ),
    );
  });
}
