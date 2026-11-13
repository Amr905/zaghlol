import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/device_api.g.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';

class _FakeHost extends DeviceSecurityHostApi {
  Object result = NativeAuthOutcome.success;
  String? reason;

  @override
  Future<NativeAuthOutcome> authenticate(String reason) async {
    this.reason = reason;
    final r = result;
    if (r is NativeAuthOutcome) return r;
    throw r;
  }

  @override
  Future<bool> isDeviceRooted() async => false;

  @override
  Future<bool> isDeviceSecure() async => true;

  @override
  Future<void> setSecureWindow(bool secure) async {}
}

void main() {
  test('every native outcome maps to the app outcome', () async {
    final host = _FakeHost();
    final auth = HostAppAuthenticator(host);
    const expected = {
      NativeAuthOutcome.success: AuthOutcome.success,
      NativeAuthOutcome.failed: AuthOutcome.failed,
      NativeAuthOutcome.cancelled: AuthOutcome.canceled,
      NativeAuthOutcome.notAvailable: AuthOutcome.unavailable,
      NativeAuthOutcome.lockedOut: AuthOutcome.lockedOut,
    };
    for (final e in expected.entries) {
      host.result = e.key;
      expect(await auth.authenticate('why'), e.value, reason: '${e.key}');
    }
    expect(host.reason, 'why');
  });

  test('a platform error is a failed check, never a pass', () async {
    final host = _FakeHost()..result = Exception('boom');
    expect(
      await HostAppAuthenticator(host).authenticate('r'),
      AuthOutcome.failed,
    );
  });
}
