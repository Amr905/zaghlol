// T-044: the permission and settings calls of AndroidCaptureHostApi and the
// CaptureEventsApi.onPermissionChanged event, over a fake native host at the
// Pigeon channel level (the generated codec) and through PigeonCaptureHostPort.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/data/capture_host_port.dart';

const String _host = 'dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi';
const String _events = 'dev.flutter.pigeon.zaghlol.CaptureEventsApi';

CaptureCapabilities _caps({required bool sms, bool flavor = true}) =>
    CaptureCapabilities(
      smsGranted: sms,
      smsFlavor: flavor,
      notificationAccess: false,
      postNotifications: true,
      sdkInt: 34,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = AndroidCaptureHostApi.pigeonChannelCodec;

  tearDown(() {
    for (final m in [
      'getCapabilities',
      'requestSmsPermission',
      'openNotificationAccessSettings',
      'isIgnoringBatteryOptimizations',
      'requestIgnoreBatteryOptimizations',
    ]) {
      messenger.setMockMessageHandler('$_host.$m', null);
    }
  });

  test('getCapabilities of a NoSms build says smsFlavor false', () async {
    messenger.setMockMessageHandler('$_host.getCapabilities', (_) async {
      return codec.encodeMessage(<Object?>[_caps(sms: false, flavor: false)]);
    });
    final c = await PigeonCaptureHostPort().getCapabilities();
    expect(c.smsFlavor, isFalse);
    expect(c.smsGranted, isFalse);
  });

  test('requestSmsPermission returns the native answer', () async {
    for (final answer in [true, false]) {
      messenger.setMockMessageHandler('$_host.requestSmsPermission', (_) async {
        return codec.encodeMessage(<Object?>[answer]);
      });
      expect(await PigeonCaptureHostPort().requestSmsPermission(), answer);
    }
  });

  test('a NoSms build answers NOT_AVAILABLE, code only', () async {
    messenger.setMockMessageHandler('$_host.requestSmsPermission', (_) async {
      return codec.encodeMessage(<Object?>['NOT_AVAILABLE', null, null]);
    });
    await expectLater(
      PigeonCaptureHostPort().requestSmsPermission(),
      throwsA(
        isA<CaptureHostException>().having(
          (e) => e.platformCode,
          'code',
          'NOT_AVAILABLE',
        ),
      ),
    );
  });

  test('the settings links and the battery state reach the host', () async {
    final calls = <String>[];
    for (final m in [
      'openNotificationAccessSettings',
      'requestIgnoreBatteryOptimizations',
    ]) {
      messenger.setMockMessageHandler('$_host.$m', (_) async {
        calls.add(m);
        return codec.encodeMessage(<Object?>[null]);
      });
    }
    messenger.setMockMessageHandler('$_host.isIgnoringBatteryOptimizations', (
      _,
    ) async {
      return codec.encodeMessage(<Object?>[true]);
    });
    final port = PigeonCaptureHostPort();
    await port.openNotificationAccessSettings();
    await port.requestIgnoreBatteryOptimizations();
    expect(await port.isIgnoringBatteryOptimizations(), isTrue);
    expect(calls, [
      'openNotificationAccessSettings',
      'requestIgnoreBatteryOptimizations',
    ]);
  });

  test('onPermissionChanged delivers the new capabilities', () async {
    final seen = <CaptureCapabilities>[];
    final handler = _Events(seen.add);
    CaptureEventsApi.setUp(handler);
    addTearDown(() => CaptureEventsApi.setUp(null));
    await messenger.handlePlatformMessage(
      '$_events.onPermissionChanged',
      CaptureEventsApi.pigeonChannelCodec.encodeMessage(<Object?>[
        _caps(sms: false),
      ]),
      (_) {},
    );
    expect(seen, hasLength(1));
    expect(seen.single.smsGranted, isFalse);
    expect(seen.single.smsFlavor, isTrue);
  });
}

final class _Events extends CaptureEventsApi {
  _Events(this.onChanged);

  final void Function(CaptureCapabilities) onChanged;

  @override
  void onPermissionChanged(CaptureCapabilities c) => onChanged(c);

  @override
  void onSpoolChanged(int pendingCount) {}
}
