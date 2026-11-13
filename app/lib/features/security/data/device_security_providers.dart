// T-103: Dart side of the DeviceSecurityHostApi (platform-channels section 5)
// and the authenticator over it. Tests override both providers with fakes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_api.g.dart';

/// The native switches: root heuristic, secure window, passcode check.
final deviceSecurityHostProvider = Provider<DeviceSecurityHostApi>(
  (ref) => DeviceSecurityHostApi(),
  name: 'deviceSecurityHostProvider',
);

/// FR-SEC-07: true when the device looks rooted or jailbroken. Best effort
/// and never blocks: any failure reads as "not detected".
final deviceRootedProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(deviceSecurityHostProvider).isDeviceRooted();
  } on Object {
    return false;
  }
}, name: 'deviceRootedProvider');

/// How one unlock attempt ended. Never carries platform text.
enum AuthOutcome {
  success,

  /// The check ran and the user did not pass it (wrong face, wrong PIN).
  failed,

  /// The user or the system dismissed the prompt.
  canceled,

  /// The phone has no screen lock or no usable biometric hardware.
  unavailable,

  /// Too many wrong tries; the OS blocks the prompt for a while.
  lockedOut,
}

abstract interface class AppAuthenticator {
  /// Asks the OS to verify the user. Biometrics first, the device passcode as
  /// the fallback (A-08): `biometricOnly` is always false.
  Future<AuthOutcome> authenticate(String reason);
}

/// Calls the native prompt through [DeviceSecurityHostApi.authenticate].
class HostAppAuthenticator implements AppAuthenticator {
  HostAppAuthenticator(this._host);

  final DeviceSecurityHostApi _host;

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    try {
      return switch (await _host.authenticate(reason)) {
        NativeAuthOutcome.success => AuthOutcome.success,
        NativeAuthOutcome.failed => AuthOutcome.failed,
        NativeAuthOutcome.cancelled => AuthOutcome.canceled,
        NativeAuthOutcome.notAvailable => AuthOutcome.unavailable,
        NativeAuthOutcome.lockedOut => AuthOutcome.lockedOut,
      };
    } on Object {
      // Anything else is a failed check, never a pass.
      return AuthOutcome.failed;
    }
  }
}

final appAuthenticatorProvider = Provider<AppAuthenticator>(
  (ref) => HostAppAuthenticator(ref.watch(deviceSecurityHostProvider)),
  name: 'appAuthenticatorProvider',
);
