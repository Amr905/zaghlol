// FU-194: the Dart side of the restore's native drain hold
// (platform-channels.md 1.4). While a restore swaps the database files the
// native headless drain (Android WorkManager engine, iOS App Intent /
// BGAppRefreshTask engine) must not open the database. The UI engine's own
// writes are stopped by IngestionPauseGate; this stops the other engine.
// Nothing here carries message content.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../core/platform/capture_api.g.dart';

/// A drain-hold call failed. [failure] carries the platform code only.
final class DrainHoldException extends SafeException {
  DrainHoldException(this.failure) : super(failure.code);

  final PlatformFailure failure;
}

abstract interface class NativeDrainHold {
  /// Sets or renews the hold for [ttl] (native caps it at 10 min). Returns
  /// true while a headless drain is still active (it was asked to stop).
  /// Throws [DrainHoldException]; then no hold is set.
  Future<bool> hold(Duration ttl);

  /// True while a headless drain is active.
  Future<bool> headlessActive();

  /// Clears the hold (idempotent). Throws [DrainHoldException].
  Future<void> release();
}

/// Platforms without a native headless drain.
final class NoNativeDrainHold implements NativeDrainHold {
  const NoNativeDrainHold();

  @override
  Future<bool> hold(Duration ttl) async => false;

  @override
  Future<bool> headlessActive() async => false;

  @override
  Future<void> release() async {}
}

final class AndroidNativeDrainHold implements NativeDrainHold {
  AndroidNativeDrainHold([AndroidCaptureHostApi? api])
    : _api = api ?? AndroidCaptureHostApi();

  final AndroidCaptureHostApi _api;

  @override
  Future<bool> hold(Duration ttl) =>
      _guard(() => _api.holdDrain(ttl.inMilliseconds));

  @override
  Future<bool> headlessActive() => _guard(_api.isHeadlessDrainActive);

  @override
  Future<void> release() => _guard(_api.releaseDrainHold);
}

final class IosNativeDrainHold implements NativeDrainHold {
  IosNativeDrainHold([IosCaptureHostApi? api])
    : _api = api ?? IosCaptureHostApi();

  final IosCaptureHostApi _api;

  @override
  Future<bool> hold(Duration ttl) =>
      _guard(() => _api.holdDrain(ttl.inMilliseconds));

  @override
  Future<bool> headlessActive() => _guard(_api.isHeadlessDrainActive);

  @override
  Future<void> release() => _guard(_api.releaseDrainHold);
}

Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw DrainHoldException(PlatformFailure.fromChannel(e.code));
  } on Exception {
    throw DrainHoldException(PlatformFailure.fromChannel(null));
  }
}

/// The drain hold of this platform.
NativeDrainHold platformNativeDrainHold({TargetPlatform? platform}) {
  if (kIsWeb) return const NoNativeDrainHold();
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => AndroidNativeDrainHold(),
    TargetPlatform.iOS => IosNativeDrainHold(),
    _ => const NoNativeDrainHold(),
  };
}

final nativeDrainHoldProvider = Provider<NativeDrainHold>(
  (ref) => platformNativeDrainHold(),
  name: 'nativeDrainHoldProvider',
);
