// Pigeon contract: device (T-004). Names only; methods, data classes and
// error handling are added by the owner task of each API, following
// docs/03-technical/platform-channels.md. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/device_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut:
        'android/app/src/main/kotlin/app/zaghlol/platform/device/DeviceApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.device',
      errorClassName: 'DeviceApiError',
    ),
    swiftOut: 'ios/Runner/Platform/DeviceApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'DeviceApiError'),
  ),
)

@HostApi()
abstract class DeviceSecurityHostApi {}

@HostApi()
abstract class WidgetBridgeHostApi {}
