// FU-194: the drain-hold contract (platform-channels.md 1.4) over fake
// native hosts at the Pigeon channel level, on both platforms: the ttl goes
// out in ms, the answers come back, native errors stay code-only.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/native_drain_hold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = ['holdDrain', 'isHeadlessDrainActive', 'releaseDrainHold'];

  for (final (name, prefix, codec, make) in [
    (
      'android',
      'dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi',
      AndroidCaptureHostApi.pigeonChannelCodec,
      () => AndroidNativeDrainHold() as NativeDrainHold,
    ),
    (
      'ios',
      'dev.flutter.pigeon.zaghlol.IosCaptureHostApi',
      IosCaptureHostApi.pigeonChannelCodec,
      () => IosNativeDrainHold() as NativeDrainHold,
    ),
  ]) {
    group(name, () {
      tearDown(() {
        for (final m in methods) {
          messenger.setMockMessageHandler('$prefix.$m', null);
        }
      });

      test(
        'hold sends the ttl in ms and returns whether a drain is active',
        () async {
          Object? sent;
          messenger.setMockMessageHandler('$prefix.holdDrain', (data) async {
            sent = (codec.decodeMessage(data)! as List<Object?>)[0];
            return codec.encodeMessage(<Object?>[true]);
          });
          expect(await make().hold(const Duration(minutes: 10)), isTrue);
          expect(sent, 600000);
        },
      );

      test('headlessActive and release reach the host', () async {
        final calls = <String>[];
        messenger
          ..setMockMessageHandler('$prefix.isHeadlessDrainActive', (_) async {
            calls.add('active');
            return codec.encodeMessage(<Object?>[false]);
          })
          ..setMockMessageHandler('$prefix.releaseDrainHold', (_) async {
            calls.add('release');
            return codec.encodeMessage(<Object?>[null]);
          });
        final h = make();
        expect(await h.headlessActive(), isFalse);
        await h.release();
        expect(calls, ['active', 'release']);
      });

      test('native errors become code-only DrainHoldExceptions', () async {
        messenger.setMockMessageHandler('$prefix.holdDrain', (_) async {
          return codec.encodeMessage(<Object?>['IO_ERROR', 'text', 'x']);
        });
        await expectLater(
          make().hold(const Duration(minutes: 1)),
          throwsA(
            isA<DrainHoldException>().having(
              (e) => e.failure.code,
              'code',
              'PLATFORM_IO_ERROR',
            ),
          ),
        );
      });
    });
  }

  test('platforms without a headless drain get the no-op hold', () async {
    final h = platformNativeDrainHold(platform: TargetPlatform.linux);
    expect(h, isA<NoNativeDrainHold>());
    expect(await h.hold(const Duration(minutes: 1)), isFalse);
    expect(
      platformNativeDrainHold(platform: TargetPlatform.iOS),
      isA<IosNativeDrainHold>(),
    );
    expect(
      platformNativeDrainHold(platform: TargetPlatform.android),
      isA<AndroidNativeDrainHold>(),
    );
  });
}
