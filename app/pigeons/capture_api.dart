// Pigeon contract: capture (T-004). Names only; methods, data classes and
// error handling are added by the owner task of each API, following
// docs/03-technical/platform-channels.md. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/capture_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/capture/CaptureApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.capture',
      errorClassName: 'CaptureApiError',
    ),
    swiftOut: 'ios/Runner/Platform/CaptureApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'CaptureApiError'),
  ),
)
@HostApi()
abstract class AndroidCaptureHostApi {}

@HostApi()
abstract class IosCaptureHostApi {}

@FlutterApi()
abstract class CaptureEventsApi {}
