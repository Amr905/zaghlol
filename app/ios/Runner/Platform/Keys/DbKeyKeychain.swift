import Foundation
import Security

/// Thin seam over the Keychain so tests can drive every OSStatus.
protocol KeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
  func add(_ attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

/// The real Keychain.
struct SystemKeychain: KeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result as? Data)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

/// Result of a slot read. `value` is set only for `.found`.
struct SlotRead {
  let status: SecretStatusMsg
  let value: Data?
  let attempts: Int
}

/// Thrown by writes; the host maps it to `KEY_STORE_FAILED` with no message.
struct KeyStoreFailure: Error {}

/// One secret slot (platform-channels §5).
protocol SecretSlotStore: AnyObject {
  func read() -> SlotRead
  /// Stores `candidate` unless a usable secret exists; returns the stored value.
  func createIfAbsent(_ candidate: Data) throws -> Data
  /// Deletes this slot only. Idempotent.
  func delete() throws
}

/// T-015: K_db as a Keychain generic password (design note §2).
///
/// Service `app.zaghlol.keys`, account `db_key_v1`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable.
/// Queries always name service and account, so the D-62 seat-key items are
/// never touched.
///
/// Access group (S-3): every query and add names the app's own
/// application-identifier group (`<AppIdentifierPrefix><bundle id>`, never a
/// shared group), so a future `keychain-access-groups` entitlement (T-008)
/// can't move K_db into a group the Share Extension can read. The prefix comes
/// from the Info.plist key `AppIdentifierPrefix` (= `$(AppIdentifierPrefix)`).
/// An unsigned build has no prefix; it then has no other group either, and the
/// attribute is omitted.
///
/// Reads classify: `errSecSuccess` with 32 bytes → found, with another length
/// → unusable; `errSecItemNotFound` → notFound; `errSecInteractionNotAllowed`
/// (before first unlock) and **every other status** → unavailable.
///
/// Every non-found read is retried on the 100/300/900 ms schedule (S-1): one
/// `found` wins; notFound or unusable is returned only when every attempt
/// agrees, and any disagreement is unavailable. Nothing here logs (FU-050).
final class DbKeyKeychain: SecretSlotStore {
  static let service = "app.zaghlol.keys"
  static let account = "db_key_v1"
  static let keyLength = 32

  /// Runner's own application-identifier group; nil in unsigned builds.
  static let appAccessGroup: String? = resolveAccessGroup(
    prefix: Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
    bundleId: Bundle.main.bundleIdentifier)

  let accessGroup: String?
  private let client: KeychainClient
  private let retryDelaysMs: [UInt32]
  private let sleeper: (UInt32) -> Void
  private let lock = NSLock()

  init(
    client: KeychainClient = SystemKeychain(),
    accessGroup: String? = DbKeyKeychain.appAccessGroup,
    retryDelaysMs: [UInt32] = [100, 300, 900],
    sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) }
  ) {
    self.client = client
    self.accessGroup = accessGroup
    self.retryDelaysMs = retryDelaysMs
    self.sleeper = sleeper
  }

  // MARK: Item attributes (asserted by SecretStoreTests)

  /// `<prefix><bundle id>`, or nil when the prefix was not expanded (unsigned
  /// build) or either part is missing.
  static func resolveAccessGroup(prefix: String?, bundleId: String?) -> String? {
    guard let prefix = prefix, let bundleId = bundleId, !bundleId.isEmpty,
      !prefix.isEmpty, !prefix.contains("$(")
    else { return nil }
    return (prefix.hasSuffix(".") ? prefix : prefix + ".") + bundleId
  }

  /// Identifies this item and nothing else.
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

  static func readQuery(accessGroup: String?) -> [String: Any] {
    var q = itemQuery(accessGroup: accessGroup)
    q[kSecReturnData as String] = kCFBooleanTrue as Any
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    return q
  }

  static func addAttributes(value: Data, accessGroup: String?) -> [String: Any] {
    var q = itemQuery(accessGroup: accessGroup)
    q[kSecValueData as String] = value
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return q
  }

  /// OSStatus → read class (design note §2).
  static func classify(status: OSStatus, data: Data?) -> SlotRead {
    switch status {
    case errSecSuccess:
      guard let data = data else { return SlotRead(status: .unavailable, value: nil, attempts: 1) }
      if data.count == keyLength { return SlotRead(status: .found, value: data, attempts: 1) }
      return SlotRead(status: .unusable, value: nil, attempts: 1)
    case errSecItemNotFound:
      return SlotRead(status: .notFound, value: nil, attempts: 1)
    default:
      // errSecInteractionNotAllowed (−25308) before first unlock, and every
      // other status: unknown, never a reason to wipe.
      return SlotRead(status: .unavailable, value: nil, attempts: 1)
    }
  }

  static func isWellFormedKey(_ bytes: Data) -> Bool {
    guard bytes.count == keyLength, let first = bytes.first else { return false }
    return bytes.contains { $0 != first }
  }

  // MARK: SecretSlotStore

  func read() -> SlotRead {
    lock.lock()
    defer { lock.unlock() }
    return readLocked(confirmNotFound: true)
  }

  func createIfAbsent(_ candidate: Data) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard DbKeyKeychain.isWellFormedKey(candidate) else { throw KeyStoreFailure() }
    // A false notFound here can't overwrite: SecItemAdd never replaces an
    // existing item (errSecDuplicateItem → the winner is read back), so this
    // read needs no confirmation of absence.
    let existing = readLocked(confirmNotFound: false)
    switch existing.status {
    case .found:
      guard let value = existing.value else { throw KeyStoreFailure() }
      return value
    case .notFound:
      break
    case .unusable, .unavailable:
      // An unusable item must be deleted first (the caller decides, under the
      // lease, that no database depends on it). Unknown state: never overwrite.
      throw KeyStoreFailure()
    }
    let status = client.add(DbKeyKeychain.addAttributes(value: candidate, accessGroup: accessGroup))
    if status == errSecDuplicateItem {
      // Another writer won; return its value if it is usable.
      let winner = readOnce()
      guard winner.status == .found, let value = winner.value else { throw KeyStoreFailure() }
      return value
    }
    guard status == errSecSuccess else { throw KeyStoreFailure() }
    let check = readOnce()
    guard check.status == .found, let stored = check.value, constantTimeEqual(stored, candidate)
    else {
      _ = client.delete(DbKeyKeychain.itemQuery(accessGroup: accessGroup))
      throw KeyStoreFailure()
    }
    return candidate
  }

  func delete() throws {
    lock.lock()
    defer { lock.unlock() }
    let status = client.delete(DbKeyKeychain.itemQuery(accessGroup: accessGroup))
    guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreFailure() }
  }

  // MARK: Private

  /// S-1: retries every non-found result; see the type comment. With
  /// `confirmNotFound == false`, a first-attempt notFound returns at once.
  private func readLocked(confirmNotFound: Bool) -> SlotRead {
    var first: SecretStatusMsg?
    var agree = true
    var attempts = 0
    while true {
      attempts += 1
      let r = readOnce()
      if r.status == .found {
        return SlotRead(status: .found, value: r.value, attempts: attempts)
      }
      if let f = first {
        if r.status != f { agree = false }
      } else {
        first = r.status
      }
      if !confirmNotFound && agree && first == .notFound {
        return SlotRead(status: .notFound, value: nil, attempts: attempts)
      }
      if attempts > retryDelaysMs.count { break }
      sleeper(retryDelaysMs[attempts - 1])
    }
    let status: SecretStatusMsg = agree ? (first ?? .unavailable) : .unavailable
    return SlotRead(status: status, value: nil, attempts: attempts)
  }

  private func readOnce() -> SlotRead {
    let (status, data) = client.copyMatching(DbKeyKeychain.readQuery(accessGroup: accessGroup))
    return DbKeyKeychain.classify(status: status, data: data)
  }

  private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
    return diff == 0
  }
}
