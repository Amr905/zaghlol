// T-008: the Dart side of the spool contract (platform-channels.md §2:
// drainSpool / ackSpool; T-041: holdSpool, FU-105). Errors become code-only exceptions; a code that is
// not UPPER_SNAKE becomes PLATFORM_UNKNOWN (FU-034), so nothing a native
// component puts in an error can carry message text further.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../core/platform/capture_api.g.dart';

/// A spool call failed. [failure] carries the platform code only.
final class SpoolPortException extends SafeException {
  SpoolPortException(this.failure) : super(failure.code);

  final PlatformFailure failure;
}

abstract interface class SpoolPort {
  /// Oldest first, at most [max]. Throws [SpoolPortException].
  Future<List<SpoolEntry>> drain(int max);

  /// Idempotent. Call only after the DB commit returned.
  Future<void> ack(List<String> ids);

  /// T-041 (FU-105): moves entries the use case could not store even alone
  /// (`IngestBatchResult.kept`) to the held area; native accepts only ids
  /// this engine drained. Call after [ack]. Throws [SpoolPortException].
  Future<void> hold(List<String> ids);
}

final class PigeonSpoolPort implements SpoolPort {
  PigeonSpoolPort([AndroidCaptureHostApi? api])
    : _api = api ?? AndroidCaptureHostApi();

  final AndroidCaptureHostApi _api;

  @override
  Future<List<SpoolEntry>> drain(int max) => _guard(() => _api.drainSpool(max));

  @override
  Future<void> ack(List<String> ids) => _guard(() => _api.ackSpool(ids));

  @override
  Future<void> hold(List<String> ids) => _guard(() => _api.holdSpool(ids));

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw SpoolPortException(PlatformFailure.fromChannel(e.code));
    } on Exception {
      throw SpoolPortException(PlatformFailure.fromChannel(null));
    }
  }
}

/// T-062: the iOS spool (App Group container) behind the same port, so the
/// Dart drain is shared with Android. Same method semantics and error codes.
final class IosPigeonSpoolPort implements SpoolPort {
  IosPigeonSpoolPort([IosCaptureHostApi? api])
    : _api = api ?? IosCaptureHostApi();

  final IosCaptureHostApi _api;

  @override
  Future<List<SpoolEntry>> drain(int max) =>
      PigeonSpoolPort._guard(() => _api.drainSpool(max));

  @override
  Future<void> ack(List<String> ids) =>
      PigeonSpoolPort._guard(() => _api.ackSpool(ids));

  @override
  Future<void> hold(List<String> ids) =>
      PigeonSpoolPort._guard(() => _api.holdSpool(ids));
}

/// The spool port of this platform: iOS reads the App Group spool, every
/// other platform the Android host (T-062).
SpoolPort platformSpoolPort({TargetPlatform? platform}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
    ? IosPigeonSpoolPort()
    : PigeonSpoolPort();
