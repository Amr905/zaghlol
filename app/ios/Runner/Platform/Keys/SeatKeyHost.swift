import Flutter
import Foundation

/// T-179: the Pigeon `SeatKeyHostApi` (platform-channels §4b). Errors carry
/// the code `SEAT_KEY_UNAVAILABLE` only (no message, no details). Nothing
/// here logs.
final class SeatKeyHost: SeatKeyHostApi {
  static let unavailableCode = "SEAT_KEY_UNAVAILABLE"

  private let store: SeatKeyStore

  init(store: SeatKeyStore = SeatKeyStore()) {
    self.store = store
  }

  func publicKeys() throws -> [FlutterStandardTypedData] {
    try mapped { try store.publicKeys().map { FlutterStandardTypedData(bytes: $0) } }
  }

  func sign(message: FlutterStandardTypedData) throws -> [SeatSignature] {
    try mapped {
      try store.sign(message.data).map {
        SeatSignature(
          publicKey: FlutterStandardTypedData(bytes: $0.publicKey),
          signature: FlutterStandardTypedData(bytes: $0.signature))
      }
    }
  }

  func rotateForNewInstall() throws {
    try mapped { try store.rotateForNewInstall() }
  }

  /// Every failure becomes a code-only error; the original error (which could
  /// describe a key) is dropped.
  private func mapped<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch {
      throw SeatKeyApiError(code: SeatKeyHost.unavailableCode, message: nil, details: nil)
    }
  }
}

enum SeatKeyRegistration {
  /// One host (and one lock) for every engine in this process.
  static let host = SeatKeyHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolSeatKey") else { return }
    SeatKeyHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
