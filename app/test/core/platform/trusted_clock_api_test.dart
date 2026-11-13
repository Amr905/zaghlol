// T-180: the TrustedClockHostApi channel with a fake platform side, plus file
// checks on the native sources (the monotonic clock choice and the privacy
// manifest entry). Synthetic values only.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/clock_api.g.dart';

const _channel = 'dev.flutter.pigeon.zaghlol.TrustedClockHostApi.sample';

void _fakePlatform(TestDefaultBinaryMessenger m, List<Object?> reply) {
  m.setMockMessageHandler(_channel, (ByteData? _) async {
    return TrustedClockHostApi.pigeonChannelCodec.encodeMessage(reply);
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMessageHandler(_channel, null));

  test('sample() decodes wall, monotonic and boot count', () async {
    _fakePlatform(messenger, [
      ClockSample(wallMs: 1700000000000, monotonicMs: 5000, bootCount: 7),
    ]);
    final s = await TrustedClockHostApi().sample();
    expect(s.wallMs, 1700000000000);
    expect(s.monotonicMs, 5000);
    expect(s.bootCount, 7);
  });

  test('bootCount stays null (iOS)', () async {
    _fakePlatform(messenger, [
      ClockSample(wallMs: 1, monotonicMs: 2, bootCount: null),
    ]);
    expect((await TrustedClockHostApi().sample()).bootCount, isNull);
  });

  test('a platform error surfaces as PlatformException', () async {
    _fakePlatform(messenger, ['CLOCK_UNAVAILABLE', null, null]);
    expect(TrustedClockHostApi().sample(), throwsA(isA<PlatformException>()));
  });

  group('native sources', () {
    String read(String p) => File(p).readAsStringSync();

    test('iOS reads CLOCK_MONOTONIC_RAW, not a clock that stops in sleep', () {
      final src = read('ios/Runner/Clock/TrustedClockHost.swift');
      expect(src, contains('clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)'));
      expect(src, isNot(contains('systemUptime')));
      expect(src, isNot(contains('CLOCK_UPTIME_RAW')));
      expect(src, isNot(contains('bootsessionuuid')));
    });

    test('PrivacyInfo.xcprivacy declares elapsed time with reason 35F9.1', () {
      final plist = read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(plist, contains('NSPrivacyAccessedAPICategorySystemBootTime'));
      expect(plist, contains('<string>35F9.1</string>'));
    });

    test('clock hosts never log', () {
      for (final f in [
        'ios/Runner/Clock/TrustedClockHost.swift',
        'android/app/src/main/kotlin/app/zaghlol/platform/clock/TrustedClockHost.kt',
      ]) {
        expect(
          read(f),
          isNot(matches(RegExp(r'\b(print|NSLog|os_log|Log\.[a-z])\('))),
          reason: f,
        );
      }
    });
  });
}
