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
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable,
/// default access group (Runner only). Queries always name service and
/// account, so the D-62 seat-key items are never touched.
///
/// Reads classify: `errSecSuccess` with 32 bytes → found, with another length
/// → unusable; `errSecItemNotFound` → notFound; `errSecInteractionNotAllowed`
/// (before first unlock) and **every other status** → unavailable, after
/// retries. Nothing here logs (FU-050).
final class DbKeyKeychain: SecretSlotStore {
  static let service = "app.zaghlol.keys"
  static let account = "db_key_v1"
  static let keyLength = 32

  private let client: KeychainClient
  private let retryDelaysMs: [UInt32]
  private let sleeper: (UInt32) -> Void
  private let lock = NSLock()

  init(
    client: KeychainClient = SystemKeychain(),
    retryDelaysMs: [UInt32] = [100, 300, 900],
    sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) }
  ) {
    self.client = client
    self.retryDelaysMs = retryDelaysMs
    self.sleeper = sleeper
  }

  // MARK: Item attributes (asserted by SecretStoreTests)

  /// Identifies this item and nothing else.
  static func itemQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }

  static func readQuery() -> [String: Any] {
    var q = itemQuery()
    q[kSecReturnData as String] = kCFBooleanTrue as Any
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    return q
  }

  static func addAttributes(value: Data) -> [String: Any] {
    var q = itemQuery()
    q[kSecValueData as String] = value
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock // NEGATIVE PROOF (c)
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
    return readLocked()
  }

  func createIfAbsent(_ candidate: Data) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard DbKeyKeychain.isWellFormedKey(candidate) else { throw KeyStoreFailure() }
    let existing = readLocked()
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
    let status = client.add(DbKeyKeychain.addAttributes(value: candidate))
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
      _ = client.delete(DbKeyKeychain.itemQuery())
      throw KeyStoreFailure()
    }
    return candidate
  }

  func delete() throws {
    lock.lock()
    defer { lock.unlock() }
    let status = client.delete(DbKeyKeychain.itemQuery())
    guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyStoreFailure() }
  }

  // MARK: Private

  private func readLocked() -> SlotRead {
    var attempts = 0
    while true {
      attempts += 1
      let r = readOnce()
      if r.status != .unavailable || attempts > retryDelaysMs.count {
        return SlotRead(status: r.status, value: r.value, attempts: attempts)
      }
      sleeper(retryDelaysMs[attempts - 1])
    }
  }

  private func readOnce() -> SlotRead {
    let (status, data) = client.copyMatching(DbKeyKeychain.readQuery())
    return DbKeyKeychain.classify(status: status, data: data)
  }

  private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
    return diff == 0
  }
}
