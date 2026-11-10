import Flutter
import Foundation

/// Native error codes (platform-channels §6). Code only: no message, no
/// details cross the boundary.
enum SecretStoreErrors {
  static let keyStoreFailed = "KEY_STORE_FAILED"
  static let leaseTimeout = "LEASE_TIMEOUT"

  static func error(_ code: String) -> SecretStoreApiError {
    SecretStoreApiError(code: code, message: nil, details: nil)
  }
}

/// T-015: the Pigeon `SecretStoreHostApi` (platform-channels §5). Work runs on
/// a background queue (taking the lease can block); replies go to the main
/// queue. Every failure is a code-only error; nothing is logged (FU-050).
final class SecretStoreHost: SecretStoreHostApi {
  private let slots: (SecretSlotMsg) -> SecretSlotStore
  private let leases: BootstrapLeaseManager
  private let worker: (@escaping () -> Void) -> Void
  private let main: (@escaping () -> Void) -> Void

  init(
    slots: @escaping (SecretSlotMsg) -> SecretSlotStore,
    leases: BootstrapLeaseManager = .process,
    worker: @escaping (@escaping () -> Void) -> Void = {
      DispatchQueue.global(qos: .userInitiated).async(execute: $0)
    },
    main: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
  ) {
    self.slots = slots
    self.leases = leases
    self.worker = worker
    self.main = main
  }

  func acquireBootstrapLease(
    timeoutMs: Int64, completion: @escaping (Result<Int64, Error>) -> Void
  ) {
    dispatch(completion) {
      guard let lease = self.leases.acquire(timeoutMs: timeoutMs) else {
        throw SecretStoreErrors.error(SecretStoreErrors.leaseTimeout)
      }
      return lease
    }
  }

  func releaseBootstrapLease(lease: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    dispatch(completion) { self.leases.release(lease) }
  }

  func read(slot: SecretSlotMsg, completion: @escaping (Result<SecretReadMsg, Error>) -> Void) {
    dispatch(completion) {
      let r = self.slots(slot).read()
      let value = r.status == .found ? r.value.map { FlutterStandardTypedData(bytes: $0) } : nil
      return SecretReadMsg(status: r.status, value: value, attempts: Int64(r.attempts))
    }
  }

  func createIfAbsent(
    lease: Int64, slot: SecretSlotMsg, candidate: FlutterStandardTypedData,
    completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
  ) {
    dispatch(completion) {
      try self.requireLease(lease)
      let stored = try self.slots(slot).createIfAbsent(candidate.data)
      return FlutterStandardTypedData(bytes: stored)
    }
  }

  func delete(lease: Int64, slot: SecretSlotMsg, completion: @escaping (Result<Void, Error>) -> Void)
  {
    dispatch(completion) {
      try self.requireLease(lease)
      try self.slots(slot).delete()
    }
  }

  private func requireLease(_ lease: Int64) throws {
    guard leases.isValid(lease) else {
      throw SecretStoreErrors.error(SecretStoreErrors.leaseTimeout)
    }
  }

  /// Runs `body` on the worker and completes on the main queue with a
  /// code-only error on failure.
  private func dispatch<T>(
    _ completion: @escaping (Result<T, Error>) -> Void, _ body: @escaping () throws -> T
  ) {
    worker {
      let result: Result<T, Error>
      do {
        result = .success(try body())
      } catch let e as SecretStoreApiError {
        result = .failure(SecretStoreErrors.error(e.code))
      } catch {
        result = .failure(SecretStoreErrors.error(SecretStoreErrors.keyStoreFailed))
      }
      self.main { completion(result) }
    }
  }
}

/// Registers the secret store on an engine. Every engine that opens the
/// database must call this; all engines share one store and one lease.
enum SecretStoreRegistration {
  static let dbKey = DbKeyKeychain()
  static let host = SecretStoreHost(slots: { slot in
    switch slot {
    case .dbKey: return dbKey
    }
  })

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolSecretStore") else { return }
    SecretStoreHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
