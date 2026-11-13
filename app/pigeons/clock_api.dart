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
abstract class TrustedClockHostApi {
  /// One consistent sample. Never sent off the device (Apple required-reason
  /// API 35F9.1: elapsed time inside the app).
  ClockSample sample();
}

class ClockSample {
  ClockSample({
    required this.wallMs,
    required this.monotonicMs,
    required this.bootCount,
  });

  /// Epoch ms (System.currentTimeMillis / Date().timeIntervalSince1970).
  int wallMs;

  /// Android SystemClock.elapsedRealtime(); iOS
  /// clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e6 (counts sleep).
  int monotonicMs;

  /// Android Settings.Global.BOOT_COUNT; iOS null (no public boot identifier).
  int? bootCount;
}

@HostApi()
abstract class SeatKeyHostApi {}
