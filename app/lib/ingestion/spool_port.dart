// T-008: the Dart side of the spool contract (platform-channels.md §2:
// drainSpool / ackSpool). Errors become code-only exceptions; a code that is
// not UPPER_SNAKE becomes PLATFORM_UNKNOWN (FU-034), so nothing a native
// component puts in an error can carry message text further.

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
}

final class PigeonSpoolPort implements SpoolPort {
  PigeonSpoolPort([AndroidCaptureHostApi? api])
    : _api = api ?? AndroidCaptureHostApi();

  final AndroidCaptureHostApi _api;

  @override
  Future<List<SpoolEntry>> drain(int max) => _guard(() => _api.drainSpool(max));

  @override
  Future<void> ack(List<String> ids) => _guard(() => _api.ackSpool(ids));

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
