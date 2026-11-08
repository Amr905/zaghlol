// Pigeon contract: clock (T-004). Names only; methods, data classes and
// error handling are added by the owner task of each API, following
// docs/03-technical/platform-channels.md. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/clock_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut:
        'android/app/src/main/kotlin/app/zaghlol/platform/clock/ClockApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.clock',
      errorClassName: 'ClockApiError',
    ),
    swiftOut: 'ios/Runner/Platform/ClockApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'ClockApiError'),
  ),
)
@HostApi()
abstract class TrustedClockHostApi {}

@HostApi()
abstract class SeatKeyHostApi {}
