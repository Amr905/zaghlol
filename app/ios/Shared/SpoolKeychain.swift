import Foundation
import Security

/// Thin seam over the Keychain so tests can drive every OSStatus. Results
/// are the item's attribute dictionary (with `v_Data`).
protocol SpoolKeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, [String: Any]?)
  func add(_ attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemSpoolKeychain: SpoolKeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, [String: Any]?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result as? [String: Any])
  }
  func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
  func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// The spool key could not be read or created now (before first unlock, a
/// Keychain error). Transient: nothing was deleted.
struct SpoolKeyUnavailable: Error {}

/// T-062 (platform-channels.md 1.3): the spool key, 32 random bytes in a
/// generic-password Keychain item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// never synchronizable, in the **shared** access group so the Share
/// Extension and the App Intents can write entries the app reads.
///
/// Reads classify like `DbKeyKeychain`: success with 32 bytes is found,
/// another length is unusable, `errSecItemNotFound` is notFound; every other
/// status (including `errSecInteractionNotAllowed` before first unlock) is
/// unavailable and never leads to a delete or a new key. An unusable item is
/// deleted and recreated only when every attempt on the 100/300/900 ms
/// schedule agrees. A concurrent create (app and extension) is resolved by
/// `errSecDuplicateItem`: the loser reads the winner's key. Nothing is logged.
final class SpoolKeychain {
  static let service = "app.zaghlol.spool"
  static let account = "spool_key_v1"
  static let keyLength = 32

  struct Loaded {
    let key: Data
    /// Item creation time (epoch ms); nil when the Keychain gives none.
    let createdAtMs: Int64?
  }

  private enum Read {
    case found(Loaded), notFound, unusable, unavailable
  }

  private let client: SpoolKeychainClient
  private let accessGroup: String?
  private let retryDelaysMs: [UInt32]
  private let sleeper: (UInt32) -> Void
  private let random: () -> Data?

  init(
    client: SpoolKeychainClient = SystemSpoolKeychain(),
    accessGroup: String? = ZaghlolSharedGroups.keychainGroup(),
    retryDelaysMs: [UInt32] = [100, 300, 900],
    sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) },
    random: @escaping () -> Data? = SpoolKeychain.secureRandomKey
  ) {
    self.client = client
    self.accessGroup = accessGroup
    self.retryDelaysMs = retryDelaysMs
    self.sleeper = sleeper
    self.random = random
  }

  static func secureRandomKey() -> Data? {
    var bytes = [UInt8](repeating: 0, count: keyLength)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      return nil
    }
    return Data(bytes)
  }

  /// Asserted by tests: identifies this item and nothing else.
  static func itemQuery(accessGroup: String?) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
    if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
    return q
  }

  static func addAttributes(accessGroup: String?, key: Data) -> [String: Any] {
    var a = itemQuery(accessGroup: accessGroup)
    a[kSecValueData as String] = key
    a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return a
  }

  /// Outcome of `existing()`. No case carries anything printable.
  enum Existing {
    case found(Loaded)
    /// Every attempt agreed there is no item.
    case notFound
    /// Locked, busy, unusable or the attempts disagreed: proves nothing.
    case unavailable
  }

  /// The key if it exists. Never creates, deletes or replaces anything (T-063,
  /// FU-196: the Guard reads the user file with it, and a read before the
  /// first unlock must not mint a key that orphans the file). An unusable
  /// item is reported as unavailable: only `loadOrCreate` may replace it.
  func existing() -> Existing {
    switch readWithRetries() {
    case .found(let l): return .found(l)
    case .notFound: return .notFound
    case .unusable, .unavailable: return .unavailable
    }
  }

  /// This item's query (service, account, access group); tests compare it.
  var query: [String: Any] { Self.itemQuery(accessGroup: accessGroup) }

  /// The key, created on first use. Throws `SpoolKeyUnavailable` for any
  /// transient failure.
  func loadOrCreate() throws -> Loaded {
    switch readWithRetries() {
    case .found(let l): return l
    case .unavailable: throw SpoolKeyUnavailable()
    case .unusable:
      // Every attempt agreed the item is not a 32-byte key: replace it.
      _ = client.delete(Self.itemQuery(accessGroup: accessGroup))
      return try create()
    case .notFound: return try create()
    }
  }

  private func create() throws -> Loaded {
    guard let key = random() else { throw SpoolKeyUnavailable() }
    let status = client.add(Self.addAttributes(accessGroup: accessGroup, key: key))
    if status == errSecSuccess {
      if case .found(let l) = readOnce() { return l }
      return Loaded(key: key, createdAtMs: nil)
    }
    if status == errSecDuplicateItem, case .found(let l) = readWithRetries() { return l }
    throw SpoolKeyUnavailable()
  }

  private func readOnce() -> Read {
    var q = Self.itemQuery(accessGroup: accessGroup)
    q[kSecReturnData as String] = true
    q[kSecReturnAttributes as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, dict) = client.copyMatching(q)
    switch status {
    case errSecSuccess:
      guard let data = dict?[kSecValueData as String] as? Data, data.count == Self.keyLength else {
        return .unusable
      }
      let created = (dict?[kSecAttrCreationDate as String] as? Date).map {
        Int64($0.timeIntervalSince1970 * 1000)
      }
      return .found(Loaded(key: data, createdAtMs: created))
    case errSecItemNotFound: return .notFound
    default: return .unavailable
    }
  }

  private func readWithRetries() -> Read {
    var first = readOnce()
    if case .found = first { return first }
    for delay in retryDelaysMs {
      sleeper(delay)
      let next = readOnce()
      if case .found = next { return next }
      if !Self.sameKind(first, next) { first = .unavailable }
    }
    return first
  }

  private static func sameKind(_ a: Read, _ b: Read) -> Bool {
    switch (a, b) {
    case (.notFound, .notFound), (.unusable, .unusable), (.unavailable, .unavailable): return true
    default: return false
    }
  }

  /// "Delete everything": removes this item only. Idempotent.
  func delete() {
    _ = client.delete(Self.itemQuery(accessGroup: accessGroup))
  }
}
