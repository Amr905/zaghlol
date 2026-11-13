import CryptoKit
import Foundation
import Security

// T-179: iOS seat keys (D-55, D-62; platform-channels §4b; design note in
// docs/04-tasks/tasks/T-179.md). Nothing here logs: no key, signature,
// message or Keychain value is ever printed (D-62, FU-050).

/// One usable signing key: a Secure Enclave key in production, a software key
/// in tests (the Simulator has no Secure Enclave).
protocol SeatSigningKey {
  /// X9.63 uncompressed point, 65 bytes.
  func publicKeyX963() throws -> Data
  /// ECDSA P-256 / SHA-256 over `message`, IEEE P1363 r‖s (64 bytes).
  func sign(_ message: Data) throws -> Data
}

/// Creates and loads seat keys from their wrapped bytes.
protocol SeatKeyFactory {
  var isAvailable: Bool { get }
  /// A new key and the bytes to keep in the Keychain.
  func create() throws -> (blob: Data, key: SeatSigningKey)
  func load(_ blob: Data) throws -> SeatSigningKey
}

private struct EnclaveKey: SeatSigningKey {
  let key: SecureEnclave.P256.Signing.PrivateKey

  func publicKeyX963() throws -> Data { key.publicKey.x963Representation }

  func sign(_ message: Data) throws -> Data {
    try key.signature(for: message).rawRepresentation
  }
}

/// Production keys: `SecureEnclave.P256.Signing.PrivateKey`, usable after the
/// first unlock, never on another device. `dataRepresentation` is an
/// SE-wrapped blob, useless off this iPhone.
struct SecureEnclaveSeatKeyFactory: SeatKeyFactory {
  var isAvailable: Bool { SecureEnclave.isAvailable }

  func create() throws -> (blob: Data, key: SeatSigningKey) {
    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error)
    else {
      error?.release()
      throw SeatKeyStore.Failure.unavailable
    }
    let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
    return (key.dataRepresentation, EnclaveKey(key: key))
  }

  func load(_ blob: Data) throws -> SeatSigningKey {
    EnclaveKey(key: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob))
  }
}

/// Thin seam over the Keychain calls this store makes, so tests can drive
/// every OSStatus and read the exact attribute dictionaries.
protocol SeatKeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
  func add(_ attributes: [String: Any]) -> OSStatus
  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
  func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemSeatKeychain: SeatKeychainClient {
  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

/// The seat keys of this iPhone: account `own` (this install) and
/// `earlier.<10 digits>` (earlier installs, higher = newer). At most 5 are
/// returned: own first, then up to 4 earlier keys, newest first.
///
/// Destruction rules (self-check §1): an item is deleted only when it was read
/// successfully and is proven unusable (empty or oversized bytes, or load /
/// sign / self-verify failing on every attempt), or by the FIFO cap after a
/// rotation. Every Keychain read error is `.unavailable` and deletes nothing.
/// Items under the service with any other account are never touched.
final class SeatKeyStore {
  enum Failure: Error { case unavailable }

  static let service = "app.zaghlol.seatkey"
  static let ownAccount = "own"
  static let earlierPrefix = "earlier."
  static let maxKeys = 5
  static let maxBlobBytes = 8192
  static let publicKeyLength = 65
  static let signatureLength = 64

  let accessGroup: String?
  private let client: SeatKeychainClient
  private let factory: SeatKeyFactory
  private let retryDelaysMs: [UInt32]
  private let sleeper: (UInt32) -> Void
  private let lock = NSLock()

  init(
    client: SeatKeychainClient = SystemSeatKeychain(),
    factory: SeatKeyFactory = SecureEnclaveSeatKeyFactory(),
    accessGroup: String? = DbKeyKeychain.appAccessGroup,
    retryDelaysMs: [UInt32] = [100, 300],
    sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) }
  ) {
    self.client = client
    self.factory = factory
    self.accessGroup = accessGroup
    self.retryDelaysMs = retryDelaysMs
    self.sleeper = sleeper
  }

  // MARK: Item attributes (asserted by SeatKeyTests)

  static func baseQuery(accessGroup: String?) -> [String: Any] {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    if let group = accessGroup { q[kSecAttrAccessGroup as String] = group }
    return q
  }

  static func itemQuery(account: String, accessGroup: String?) -> [String: Any] {
    var q = baseQuery(accessGroup: accessGroup)
    q[kSecAttrAccount as String] = account
    return q
  }

  static func addAttributes(account: String, blob: Data, accessGroup: String?) -> [String: Any] {
    var q = itemQuery(account: account, accessGroup: accessGroup)
    q[kSecValueData as String] = blob
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return q
  }

  static func earlierAccount(_ seq: Int) -> String {
    earlierPrefix + String(format: "%010d", seq)
  }

  /// The sequence of an `earlier.<10 digits>` account, or nil for any other.
  static func earlierSeq(_ account: String) -> Int? {
    guard account.hasPrefix(earlierPrefix) else { return nil }
    let digits = account.dropFirst(earlierPrefix.count)
    guard digits.count == 10, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
    return Int(digits)
  }

  // MARK: Operations

  /// [own, earlier…] public keys; `[]` without a Secure Enclave.
  func publicKeys() throws -> [Data] {
    guard factory.isAvailable else { return [] }
    lock.lock()
    defer { lock.unlock() }
    return try loadKeys().map { $0.publicKey }
  }

  /// Signs `message` with every key, same order. An unusable earlier key is
  /// deleted and dropped; an unusable own key is replaced by a new own key.
  func sign(_ message: Data) throws -> [(publicKey: Data, signature: Data)] {
    guard factory.isAvailable else { return [] }
    lock.lock()
    defer { lock.unlock() }
    var out: [(publicKey: Data, signature: Data)] = []
    for entry in try loadKeys() {
      if let sig = signConfirmed(entry.key, entry.publicKey, message) {
        out.append((entry.publicKey, sig))
        continue
      }
      try deleteItem(entry.account)
      guard entry.account == SeatKeyStore.ownAccount else { continue }
      // Element 0 must stay this install's key: make a new one at once.
      let fresh = try ensureOwn()
      guard let sig = signConfirmed(fresh.key, fresh.publicKey, message) else {
        throw Failure.unavailable
      }
      out.append((fresh.publicKey, sig))
    }
    return out
  }

  /// The own key becomes the newest earlier key (one atomic rename), then the
  /// oldest earlier keys beyond 4 are deleted. Without an own key: nothing.
  func rotateForNewInstall() throws {
    guard factory.isAvailable else { return }
    lock.lock()
    defer { lock.unlock() }
    let accounts = try listAccounts()
    let earlier = accounts.compactMap(SeatKeyStore.earlierSeq).sorted()
    if accounts.contains(SeatKeyStore.ownAccount) {
      let next = (earlier.last ?? 0) + 1
      let status = client.update(
        SeatKeyStore.itemQuery(account: SeatKeyStore.ownAccount, accessGroup: accessGroup),
        [kSecAttrAccount as String: SeatKeyStore.earlierAccount(next)])
      switch status {
      case errSecSuccess:
        try trim(earlier + [next])
      case errSecItemNotFound:
        try trim(earlier)  // another engine rotated first
      default:
        throw Failure.unavailable
      }
    } else {
      try trim(earlier)
    }
  }

  // MARK: Private

  private struct Entry {
    let account: String
    let key: SeatSigningKey
    let publicKey: Data
  }

  private enum Load {
    case usable(SeatSigningKey, Data)
    case unusable
    case absent
  }

  /// Own key (created when positively absent, replaced when unusable), then
  /// the newest 4 usable earlier keys.
  private func loadKeys() throws -> [Entry] {
    let accounts = try listAccounts()
    var out: [Entry] = []
    if accounts.contains(SeatKeyStore.ownAccount) {
      switch try loadItem(SeatKeyStore.ownAccount) {
      case .usable(let key, let pk):
        out.append(Entry(account: SeatKeyStore.ownAccount, key: key, publicKey: pk))
      case .unusable:
        try deleteItem(SeatKeyStore.ownAccount)
        out.append(try ensureOwn())
      case .absent:
        out.append(try ensureOwn())
      }
    } else {
      out.append(try ensureOwn())
    }
    let earlier = accounts.compactMap(SeatKeyStore.earlierSeq).sorted(by: >)
    for seq in earlier {
      if out.count >= SeatKeyStore.maxKeys { break }
      let account = SeatKeyStore.earlierAccount(seq)
      switch try loadItem(account) {
      case .usable(let key, let pk):
        // Distinct keys only (a duplicate can't be proven usable twice).
        if out.contains(where: { $0.publicKey == pk }) { continue }
        out.append(Entry(account: account, key: key, publicKey: pk))
      case .unusable:
        try deleteItem(account)
      case .absent:
        continue
      }
    }
    return out
  }

  /// The own key, creating it when absent. A concurrent writer's key wins.
  private func ensureOwn() throws -> Entry {
    let created = try factory.create()
    let pk = try created.key.publicKeyX963()
    let status = client.add(
      SeatKeyStore.addAttributes(
        account: SeatKeyStore.ownAccount, blob: created.blob, accessGroup: accessGroup))
    switch status {
    case errSecSuccess:
      return Entry(account: SeatKeyStore.ownAccount, key: created.key, publicKey: pk)
    case errSecDuplicateItem:
      if case .usable(let key, let winner) = try loadItem(SeatKeyStore.ownAccount) {
        return Entry(account: SeatKeyStore.ownAccount, key: key, publicKey: winner)
      }
      throw Failure.unavailable
    default:
      throw Failure.unavailable
    }
  }

  /// Accounts under the service; `[]` when there are none.
  private func listAccounts() throws -> [String] {
    var q = SeatKeyStore.baseQuery(accessGroup: accessGroup)
    q[kSecReturnAttributes as String] = kCFBooleanTrue as Any
    q[kSecMatchLimit as String] = kSecMatchLimitAll
    let (status, result) = client.copyMatching(q)
    switch status {
    case errSecSuccess:
      guard let items = result as? [[String: Any]] else { throw Failure.unavailable }
      return items.compactMap { $0[kSecAttrAccount as String] as? String }
    case errSecItemNotFound:
      return []
    default:
      throw Failure.unavailable
    }
  }

  private func loadItem(_ account: String) throws -> Load {
    var q = SeatKeyStore.itemQuery(account: account, accessGroup: accessGroup)
    q[kSecReturnData as String] = kCFBooleanTrue as Any
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, result) = client.copyMatching(q)
    switch status {
    case errSecSuccess:
      guard let blob = result as? Data else { throw Failure.unavailable }
      if blob.isEmpty || blob.count > SeatKeyStore.maxBlobBytes { return .unusable }
      let loaded: (SeatSigningKey, Data)? = attempt {
        let key = try self.factory.load(blob)
        let pk = try key.publicKeyX963()
        guard pk.count == SeatKeyStore.publicKeyLength, pk.first == 0x04 else { return nil }
        return (key, pk)
      }
      guard let found = loaded else { return .unusable }
      return .usable(found.0, found.1)
    case errSecItemNotFound:
      return .absent
    default:
      throw Failure.unavailable
    }
  }

  /// A signature that verifies against `publicKey`, or nil after every
  /// attempt failed.
  private func signConfirmed(_ key: SeatSigningKey, _ publicKey: Data, _ message: Data) -> Data? {
    attempt {
      let sig = try key.sign(message)
      let pub = try P256.Signing.PublicKey(x963Representation: publicKey)
      let ecdsa = try P256.Signing.ECDSASignature(rawRepresentation: sig)
      guard sig.count == SeatKeyStore.signatureLength, pub.isValidSignature(ecdsa, for: message)
      else { return nil }
      return sig
    }
  }

  /// Runs `body` once plus once per retry delay; the first non-nil wins.
  private func attempt<T>(_ body: () throws -> T?) -> T? {
    var tries = 0
    while true {
      if let value = try? body() { return value }
      if tries >= retryDelaysMs.count { return nil }
      sleeper(retryDelaysMs[tries])
      tries += 1
    }
  }

  private func deleteItem(_ account: String) throws {
    let status = client.delete(SeatKeyStore.itemQuery(account: account, accessGroup: accessGroup))
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.unavailable
    }
  }

  /// FIFO cap: keeps the newest `maxKeys - 1` earlier keys.
  private func trim(_ earlierSeqs: [Int]) throws {
    let sorted = earlierSeqs.sorted()
    let excess = sorted.count - (SeatKeyStore.maxKeys - 1)
    guard excess > 0 else { return }
    for seq in sorted.prefix(excess) { try deleteItem(SeatKeyStore.earlierAccount(seq)) }
  }
}
