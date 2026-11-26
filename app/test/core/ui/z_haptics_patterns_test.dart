// T-293: animation-synced haptic patterns, Dart side.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final native = <MethodCall>[];
  final system = <String>[];
  Object? Function(MethodCall)? nativeHandler;

  setUp(() {
    native.clear();
    system.clear();
    ZHaptics.enabled = true;
    ZHaptics.reduceMotion = false;
    nativeHandler = (c) => true;
    messenger.setMockMethodCallHandler(ZHaptics.channel, (c) async {
      native.add(c);
      return nativeHandler!(c);
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') {
        system.add(c.arguments as String);
      }
      return null;
    });
  });
  tearDown(() {
    ZHaptics.enabled = true;
    ZHaptics.reduceMotion = false;
    messenger.setMockMethodCallHandler(ZHaptics.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('timelines', () {
    expect(ZHaptics.timelineMs(ZHapticPattern.payday), [
      0,
      140,
      260,
      360,
      450,
      700,
      1300,
      1420,
    ]);
    expect(ZHaptics.timelineMs(ZHapticPattern.saved), [0, 90]);
    expect(ZHaptics.timelineMs(ZHapticPattern.oops), [0, 140]);
    expect(ZHaptics.timelineMs(ZHapticPattern.birdTap), [0]);
    final thuds = ZHaptics.hits(ZHapticPattern.payday)
        .where((h) => h.strength == ZHapticStrength.thud);
    expect(thuds.single.atMs, 700);
  });

  test('plays through the channel with the beat table', () async {
    await ZHaptics.play(ZHapticPattern.saved, reduceMotion: false);
    expect(native.single.method, 'play');
    expect((native.single.arguments as Map)['hits'], [
      [0, ZHapticStrength.click.index, 80],
      [90, ZHapticStrength.click.index, 100],
    ]);
    expect(system, isEmpty);
  });

  test('disabled: no channel call, no fallback', () async {
    ZHaptics.enabled = false;
    await ZHaptics.play(ZHapticPattern.payday, reduceMotion: false);
    expect(native, isEmpty);
    expect(system, isEmpty);
  });

  test('reduce motion: one light tick, nothing native', () async {
    await ZHaptics.play(ZHapticPattern.payday, reduceMotion: true);
    expect(native, isEmpty);
    expect(system, ['HapticFeedbackType.lightImpact']);
    ZHaptics.reduceMotion = true;
    system.clear();
    await ZHaptics.play(ZHapticPattern.oops);
    expect(system, ['HapticFeedbackType.lightImpact']);
  });

  test('channel missing: falls back without throwing', () async {
    messenger.setMockMethodCallHandler(ZHaptics.channel, null);
    await ZHaptics.play(ZHapticPattern.saved, reduceMotion: false);
    expect(system, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('native says unsupported or throws: falls back', () async {
    nativeHandler = (c) => false;
    await ZHaptics.play(ZHapticPattern.birdTap, reduceMotion: false);
    expect(system, ['HapticFeedbackType.lightImpact']);
    system.clear();
    nativeHandler = (c) => throw PlatformException(code: 'x');
    await ZHaptics.play(ZHapticPattern.birdTap, reduceMotion: false);
    expect(system, ['HapticFeedbackType.lightImpact']);
  });
}
