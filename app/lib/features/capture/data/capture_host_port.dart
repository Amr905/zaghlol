// T-047: the Dart interface over AndroidCaptureHostApi that the capture
// module uses (fakes in tests). Errors become code-only exceptions; a code
// that is not UPPER_SNAKE becomes PLATFORM_UNKNOWN (FU-034).
// T-063/T-066: IosCaptureHostPort (ios_capture_host_port.dart) is the same interface over IosCaptureHostApi
// (Guard config, spool status); the Android-only calls answer NOT_AVAILABLE.

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

  /// T-044: READ_SMS + RECEIVE_SMS, after Flutter's own rationale screen.
  /// True only if both were granted. The `*NoSms` build throws
  /// [CaptureHostException] `NOT_AVAILABLE` and never shows a system prompt.
  Future<bool> requestSmsPermission();

  /// T-044: opens the system "Notification access" list (the user grants it
  /// there; the app cannot). Show the prominent disclosure first (T-056).
  Future<void> openNotificationAccessSettings();

  /// T-044: battery-optimisation state and the system list link (Q3: never
  /// the REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog).
  Future<bool> isIgnoringBatteryOptimizations();

  Future<void> requestIgnoreBatteryOptimizations();

  /// [userConfigJson] is plaintext; the caller zeroes it after the call.
  Future<void> writeGuardConfig(Uint8List userConfigJson);

  Future<SpoolStatus> getSpoolStatus();

  Future<void> clearSpoolAlerts(int seq);

  Future<void> scheduleIngestionNow();

  /// T-042 / T-048: one page of the historical inbox scan. The query's
  /// addresses are filtered natively; throws [CaptureHostException]
  /// (`PERMISSION_DENIED`, `NOT_AVAILABLE`, `INVALID_ARGUMENT`, `IO_ERROR`).
  Future<InboxPage> queryInbox(InboxQuery query);
}

final class PigeonCaptureHostPort implements CaptureHostPort {
  PigeonCaptureHostPort([AndroidCaptureHostApi? api])
    : _api = api ?? AndroidCaptureHostApi();

  final AndroidCaptureHostApi _api;

  @override
  Future<CaptureCapabilities> getCapabilities() => _guard(_api.getCapabilities);

  @override
  Future<bool> requestSmsPermission() => _guard(_api.requestSmsPermission);

  @override
  Future<void> openNotificationAccessSettings() =>
      _guard(_api.openNotificationAccessSettings);

  @override
  Future<bool> isIgnoringBatteryOptimizations() =>
      _guard(_api.isIgnoringBatteryOptimizations);

  @override
  Future<void> requestIgnoreBatteryOptimizations() =>
      _guard(_api.requestIgnoreBatteryOptimizations);

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

  @override
  Future<InboxPage> queryInbox(InboxQuery query) =>
      _guard(() => _api.queryInbox(query));

  static Future<T> _guard<T>(Future<T> Function() call) => _guardCapture(call);
}

Future<T> _guardCapture<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw CaptureHostException(PlatformFailure.fromChannel(e.code));
  } on Exception {
    throw CaptureHostException(PlatformFailure.fromChannel(null));
  }
}
