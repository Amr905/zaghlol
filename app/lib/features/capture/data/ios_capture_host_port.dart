// T-066: the iOS adapter behind the capture module's host port. iOS has no
// SMS, notification listener, inbox or battery-optimisation surface, so those
// answer NOT_AVAILABLE (the module treats that as "not in this build", the
// same as the Play flavour). Spool status, alert clearing and the background
// refresh go to IosCaptureHostApi (T-062). Errors are code-only.
//
// The Guard config write (T-061/T-063) goes to the same Guard instance the
// App Intents use.

import 'package:flutter/services.dart';

import '../../../core/platform/capture_api.g.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'capture_host_port.dart';

final class IosCaptureHostPort implements CaptureHostPort {
  IosCaptureHostPort([IosCaptureHostApi? api])
    : _api = api ?? IosCaptureHostApi();

  final IosCaptureHostApi _api;

  static CaptureHostException _unavailable() =>
      CaptureHostException(PlatformFailure.fromChannel('NOT_AVAILABLE'));

  /// Nothing Android-specific exists here; the shared-spool channels
  /// (Shortcuts, Apple Pay) need no permission the app can query.
  @override
  Future<CaptureCapabilities> getCapabilities() async => CaptureCapabilities(
    smsGranted: false,
    smsFlavor: false,
    notificationAccess: false,
    postNotifications: false,
    sdkInt: 0,
  );

  @override
  Future<bool> requestSmsPermission() async => throw _unavailable();

  @override
  Future<void> openNotificationAccessSettings() async => throw _unavailable();

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => throw _unavailable();

  @override
  Future<void> requestIgnoreBatteryOptimizations() async =>
      throw _unavailable();

  @override
  Future<void> writeGuardConfig(Uint8List userConfigJson) =>
      _guard(() => _api.writeGuardConfig(userConfigJson));

  @override
  Future<InboxPage> queryInbox(InboxQuery query) async => throw _unavailable();

  @override
  Future<SpoolStatus> getSpoolStatus() => _guard(_api.getSpoolStatus);

  @override
  Future<void> clearSpoolAlerts(int seq) =>
      _guard(() => _api.clearSpoolAlerts(seq));

  /// iOS has no worker to expedite: this asks for the next background refresh
  /// (best effort; the foreground drain is the guarantee).
  @override
  Future<void> scheduleIngestionNow() => _guard(_api.registerBackgroundRefresh);

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
