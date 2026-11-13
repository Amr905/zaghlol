import Darwin
import Flutter
import Foundation

/// The three raw readings; a seam so tests can feed fixed values.
protocol ClockReadings {
  func wallMs() -> Int64
  func monotonicMs() -> Int64
}

/// Real readings. `CLOCK_MONOTONIC_RAW` is continuous time: it keeps counting
/// while the device sleeps (unlike the uptime clocks, which stop) and
/// restarts low after a reboot.
struct SystemClockReadings: ClockReadings {
  func wallMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000.0).rounded(.down))
  }

  func monotonicMs() -> Int64 {
    Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1_000_000)
  }
}

/// T-180: the Pigeon `TrustedClockHostApi` (platform-channels §4b). Reads
/// clocks only; no trusted-time logic (T-144, Dart). Values are never logged.
final class TrustedClockHost: TrustedClockHostApi {
  private let readings: ClockReadings

  init(readings: ClockReadings = SystemClockReadings()) {
    self.readings = readings
  }

  func sample() throws -> ClockSample {
    // Back to back so the values describe the same instant. iOS has no public
    // boot identifier, so bootCount is nil.
    let wall = readings.wallMs()
    let mono = readings.monotonicMs()
    return ClockSample(wallMs: wall, monotonicMs: mono, bootCount: nil)
  }
}

enum TrustedClockRegistration {
  static let host = TrustedClockHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolTrustedClock") else { return }
    TrustedClockHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
