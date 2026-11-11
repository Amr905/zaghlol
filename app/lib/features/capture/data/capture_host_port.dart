// T-047: the Dart interface over AndroidCaptureHostApi that the capture
// module uses (fakes in tests). Errors become code-only exceptions; a code
// that is not UPPER_SNAKE becomes PLATFORM_UNKNOWN (FU-034).

import 'package:flutter/services.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/platform/capture_api.g.dart';

/// A host call failed. [failure] carries the platform code only.
final class CaptureHostException extends SafeException {
  CaptureHostException(this.failure) : super(failure.code);

  final PlatformFailure failure;

  /// The bare platform code (`CONFIG_INVALID`, `IO_ERROR`, `NOT_AVAILABLE`).
  String get platformCode => failure.platformCode;
}

abstract interface class CaptureHostPort {
  Future<CaptureCapabilities> getCapabilities();

  /// [userConfigJson] is plaintext; the caller zeroes it after the call.
  Future<void> writeGuardConfig(Uint8List userConfigJson);

  Future<SpoolStatus> getSpoolStatus();

  Future<void> clearSpoolAlerts(int seq);

  Future<void> scheduleIngestionNow();
}

final class PigeonCaptureHostPort implements CaptureHostPort {
  PigeonCaptureHostPort([AndroidCaptureHostApi? api])
    : _api = api ?? AndroidCaptureHostApi();

  final AndroidCaptureHostApi _api;

  @override
  Future<CaptureCapabilities> getCapabilities() => _guard(_api.getCapabilities);

  @override
  Future<void> writeGuardConfig(Uint8List userConfigJson) =>
      _guard(() => _api.writeGuardConfig(userConfigJson));

  @override
  Future<SpoolStatus> getSpoolStatus() => _guard(_api.getSpoolStatus);

  @override
  Future<void> clearSpoolAlerts(int seq) =>
      _guard(() => _api.clearSpoolAlerts(seq));

  @override
  Future<void> scheduleIngestionNow() => _guard(_api.scheduleIngestionNow);

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw CaptureHostException(PlatformFailure.fromChannel(e.code));
    } on Exception {
      throw CaptureHostException(PlatformFailure.fromChannel(null));
    }
  }
}
