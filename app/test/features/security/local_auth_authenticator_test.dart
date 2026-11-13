import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';

class _FakeLocalAuth extends LocalAuthPlatform with MockPlatformInterfaceMixin {
  Object? result = true;
  AuthenticationOptions? options;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    this.options = options;
    final r = result;
    if (r is LocalAuthException) throw r;
    if (r is Exception) throw r;
    return r! as bool;
  }
}

void main() {
  late _FakeLocalAuth platform;
  late LocalAuthAuthenticator auth;

  setUp(() {
    platform = _FakeLocalAuth();
    LocalAuthPlatform.instance = platform;
    auth = LocalAuthAuthenticator();
  });

  test(
    'device passcode is allowed as the fallback (biometricOnly false)',
    () async {
      expect(await auth.authenticate('r'), AuthOutcome.success);
      expect(platform.options!.biometricOnly, isFalse);
    },
  );

  test('a failed check is failed, never success', () async {
    platform.result = false;
    expect(await auth.authenticate('r'), AuthOutcome.failed);
  });

  test('exceptions map to outcomes and are never a pass', () async {
    final cases = <Object, AuthOutcome>{
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled):
          AuthOutcome.canceled,
      const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet):
          AuthOutcome.unavailable,
      const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout):
          AuthOutcome.lockedOut,
      const LocalAuthException(code: LocalAuthExceptionCode.deviceError):
          AuthOutcome.failed,
      Exception('boom'): AuthOutcome.failed,
    };
    for (final e in cases.entries) {
      platform.result = e.key;
      expect(await auth.authenticate('r'), e.value, reason: '${e.key}');
    }
  });
}
