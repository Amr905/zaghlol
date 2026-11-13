import DeviceCheck
import Flutter
import Foundation
import Security

/// Seam over `DCAppAttestService`, so tests drive every outcome.
protocol AppAttestService {
  var isSupported: Bool { get }
  func generateKey(completion: @escaping (String?, Error?) -> Void)
  func attestKey(_ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void)
  func generateAssertion(
    _ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void)
}

/// The real App Attest service (sandbox in development builds, production
/// after TestFlight / App Store distribution; no entitlement needed).
struct SystemAppAttestService: AppAttestService {
  private var service: DCAppAttestService { DCAppAttestService.shared }

  var isSupported: Bool { service.isSupported }

  func generateKey(completion: @escaping (String?, Error?) -> Void) {
    service.generateKey(completionHandler: completion)
  }

  func attestKey(_ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void) {
    service.attestKey(keyId, clientDataHash: clientDataHash, completionHandler: completion)
  }

  func generateAssertion(
    _ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void
  ) {
    service.generateAssertion(keyId, clientDataHash: clientDataHash, completionHandler: completion)
  }
}

/// Result of reading the stored key ID.
enum AttestKeyIdRead: Equatable {
  case found(String)
  /// Positive evidence there is no usable key ID (`errSecItemNotFound`, or an
  /// item that is provably not a key ID).
  case notFound
  /// Any other Keychain status: never a reason to make a new key.
  case unavailable
}

protocol AttestKeyIdStore {
  func read() -> AttestKeyIdRead
  /// Stores `keyId` as the one install-bound key ID; false on any failure.
  func replace(_ keyId: String) -> Bool
}

/// T-178: the App Attest key ID as a Keychain generic password. Service
/// `app.zaghlol.attest`, account `app_attest_key_id_v1`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable,
/// Runner's own access group (same rule as `DbKeyKeychain`). Queries always
/// name service and account, so no other item is touched. Nothing here logs.
final class KeychainAttestKeyIdStore: AttestKeyIdStore {
  static let service = "app.zaghlol.attest"
  static let account = "app_attest_key_id_v1"

  let accessGroup: String?
  private let client: KeychainClient

  init(client: KeychainClient = SystemKeychain(), accessGroup: String? = DbKeyKeychain.appAccessGroup) {
    self.client = client
    self.accessGroup = accessGroup
  }

  static func itemQuery(accessGroup: String?) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    if let group = accessGroup { q[kSecAttrAccessGroup as String] = group }
    return q
  }

  static func addAttributes(keyId: String, accessGroup: String?) -> [String: Any] {
    var q = itemQuery(accessGroup: accessGroup)
    q[kSecValueData as String] = Data(keyId.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return q
  }

  func read() -> AttestKeyIdRead {
    var q = Self.itemQuery(accessGroup: accessGroup)
    q[kSecReturnData as String] = kCFBooleanTrue as Any
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, data) = client.copyMatching(q)
    switch status {
    case errSecSuccess:
      // Present but not a key ID (empty or not UTF-8): provably unusable.
      guard let data = data, let id = String(data: data, encoding: .utf8), !id.isEmpty else {
        return .notFound
      }
      return .found(id)
    case errSecItemNotFound:
      return .notFound
    default:
      return .unavailable
    }
  }

  func replace(_ keyId: String) -> Bool {
    let status = client.delete(Self.itemQuery(accessGroup: accessGroup))
    guard status == errSecSuccess || status == errSecItemNotFound else { return false }
    return client.add(Self.addAttributes(keyId: keyId, accessGroup: accessGroup)) == errSecSuccess
  }
}

/// T-178: the Pigeon `AttestationHostApi` on iOS (platform-channels §4a).
///
/// One install-bound App Attest key. The 32 bytes Dart passes are used
/// unchanged as `clientDataHash` for `generateAssertion` and, on a new key,
/// for `attestKey` (R2-1, R4-1(3)); native code never builds or alters the
/// hash and never sees the install ID.
///
/// A new key is made only on positive evidence: `forceNewKey`, no stored key
/// ID (`errSecItemNotFound`), or `DCError.invalidKey` from an assertion. The
/// stored key ID is replaced only after the new key has been attested, so a
/// failure on the way leaves the old one in place. Calls run one at a time
/// (two restores can't create two keys); all state is touched on the
/// callback queue (main). Errors are code-only; nothing here logs.
final class AttestationHost: AttestationHostApi {
  static let transient = "ATTEST_TRANSIENT"
  static let unavailable = "ATTEST_UNAVAILABLE"
  static let type = "app_attest"
  static let hashLength = 32

  typealias Completion = (Result<AttestationProof, Error>) -> Void

  private let service: AppAttestService
  private let store: AttestKeyIdStore
  /// Runs SDK completions on the queue that owns this host's state.
  private let hop: (@escaping () -> Void) -> Void
  private var running = false
  private var pending: [(@escaping () -> Void) -> Void] = []

  init(
    service: AppAttestService = SystemAppAttestService(),
    store: AttestKeyIdStore = KeychainAttestKeyIdStore(),
    hop: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
  ) {
    self.service = service
    self.store = store
    self.hop = hop
  }

  func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
    // Nothing to warm up on iOS.
    completion(.success(()))
  }

  func attest(
    bodyHash: FlutterStandardTypedData, forceNewKey: Bool,
    completion: @escaping (Result<AttestationProof, Error>) -> Void
  ) {
    let hash = bodyHash.data
    enqueue { done in
      self.run(hash: hash, forceNewKey: forceNewKey) { result in
        completion(result)
        done()
      }
    }
  }

  // MARK: Serialization

  private func enqueue(_ op: @escaping (_ done: @escaping () -> Void) -> Void) {
    pending.append(op)
    if !running { startNext() }
  }

  private func startNext() {
    guard !pending.isEmpty else {
      running = false
      return
    }
    running = true
    let op = pending.removeFirst()
    op { [weak self] in self?.startNext() }
  }

  // MARK: Flow

  private func run(hash: Data, forceNewKey: Bool, completion: @escaping Completion) {
    guard hash.count == Self.hashLength, service.isSupported else {
      completion(.failure(Self.error(Self.unavailable)))
      return
    }
    if forceNewKey {
      newKey(hash: hash, completion: completion)
      return
    }
    switch store.read() {
    case .unavailable, .notFound:
      newKey(hash: hash, completion: completion)
    case .found(let keyId):
      service.generateAssertion(keyId, clientDataHash: hash) { data, err in
        self.hop {
          if let assertion = data, err == nil {
            completion(
              .success(
                AttestationProof(
                  type: Self.type, keyId: keyId, assertion: assertion.base64EncodedString())))
          } else if Self.isInvalidKey(err) {
            self.newKey(hash: hash, completion: completion)
          } else {
            completion(.failure(Self.error(Self.code(for: err))))
          }
        }
      }
    }
  }

  private func newKey(hash: Data, completion: @escaping Completion) {
    service.generateKey { keyId, err in
      self.hop {
        guard let keyId = keyId, !keyId.isEmpty, err == nil else {
          completion(.failure(Self.error(Self.code(for: err))))
          return
        }
        self.service.attestKey(keyId, clientDataHash: Data(hash.reversed())) { object, err in
          self.hop {
            guard let object = object, err == nil else {
              completion(.failure(Self.error(Self.code(for: err))))
              return
            }
            // Keep only a key we can use again; the old ID stays until here.
            guard self.store.replace(keyId) else {
              completion(.failure(Self.error(Self.unavailable)))
              return
            }
            self.service.generateAssertion(keyId, clientDataHash: hash) { assertion, err in
              self.hop {
                // invalidKey on a fresh key maps to unavailable: no loop.
                guard let assertion = assertion, err == nil else {
                  completion(.failure(Self.error(Self.code(for: err))))
                  return
                }
                completion(
                  .success(
                    AttestationProof(
                      type: Self.type, keyId: keyId,
                      assertion: assertion.base64EncodedString(),
                      attestationObject: object.base64EncodedString())))
              }
            }
          }
        }
      }
    }
  }

  // MARK: Errors (platform-channels §6)

  static func isInvalidKey(_ err: Error?) -> Bool {
    guard let err = err else { return false }
    let ns = err as NSError
    return ns.domain == DCErrorDomain && ns.code == DCError.Code.invalidKey.rawValue
  }

  /// `serverUnavailable` → transient; everything else (feature unsupported,
  /// invalid input or key, unknown failure, non-DeviceCheck errors, no error
  /// with no value) → unavailable.
  static func code(for err: Error?) -> String {
    guard let err = err else { return unavailable }
    let ns = err as NSError
    if ns.domain == DCErrorDomain && ns.code == DCError.Code.serverUnavailable.rawValue {
      return transient
    }
    return unavailable
  }

  static func error(_ code: String) -> AttestationApiError {
    AttestationApiError(code: code, message: nil, details: nil)
  }
}

/// Registers the attestation host on the UI engine (restore runs in the foreground).
enum AttestationRegistration {
  static let host = AttestationHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolAttestation") else { return }
    AttestationHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
