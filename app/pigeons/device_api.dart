// Pigeon contract: device (T-004). Names only; methods, data classes and
// error handling are added by the owner task of each API, following
// docs/03-technical/platform-channels.md. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/device_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/device/DeviceApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.device',
      errorClassName: 'DeviceApiError',
    ),
    swiftOut: 'ios/Runner/Platform/DeviceApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'DeviceApiError'),
  ),
)
@HostApi()
abstract class DeviceSecurityHostApi {
  /// FR-SEC-07 heuristic: true when the device looks rooted (Android) or
  /// jailbroken (iOS). Best effort, trivially bypassable; it only drives a
  /// warning and never blocks anything.
  bool isDeviceRooted();

  /// FR-SEC-02 (T-103): true hides the app in the OS app switcher and blocks
  /// screenshots (Android FLAG_SECURE + recents screenshot off; iOS cover view
  /// while the scene is not active). false restores normal behaviour.
  void setSecureWindow(bool secure);

  /// True when the device has a passcode / PIN / pattern set (the fallback the
  /// app lock needs).
  bool isDeviceSecure();
}

@HostApi()
abstract class WidgetBridgeHostApi {}
