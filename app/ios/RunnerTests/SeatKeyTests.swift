import CryptoKit
import XCTest

@testable import Runner

/// T-179. Synthetic keys only. The Simulator has no Secure Enclave, so the
/// store logic runs with software P-256 keys over an in-memory Keychain; the
/// Secure Enclave round trip runs on a device only (skipped elsewhere).
final class SeatKeyTests: XCTestCase {
  // MARK: Fakes

  private struct SoftwareKey: SeatSigningKey {
    let key: P256.Signing.PrivateKey
    func publicKeyX963() throws -> Data { key.publicKey.x963Representation }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).rawRepresentation }
  }

  private struct Broken: Error {}

  /// Blobs listed in `bad` fail to load; `failSign` keys fail to sign.
  private final class SoftwareFactory: SeatKeyFactory {
    var isAvailable = true
    var bad: Set<Data> = []
    var failSign: Set<Data> = []
    var created = 0

    func create() throws -> (blob: Data, key: SeatSigningKey) {
      created += 1
      let k = P256.Signing.PrivateKey()
      return (k.rawRepresentation, try load(k.rawRepresentation))
    }

    func load(_ blob: Data) throws -> SeatSigningKey {
      if bad.contains(blob) { throw Broken() }
      let k = SoftwareKey(key: try P256.Signing.PrivateKey(rawRepresentation: blob))
      return failSign.contains(blob) ? FailingKey(inner: k) : k
    }
  }

  private struct FailingKey: SeatSigningKey {
    let inner: SoftwareKey
    func publicKeyX963() throws -> Data { try inner.publicKeyX963() }
    func sign(_ message: Data) throws -> Data { throw Broken() }
  }

  /// In-memory generic-password items keyed by account (one service).
  private final class FakeKeychain: SeatKeychainClient {
    var items: [String: (data: Data, attrs: [String: Any])] = [:]
    var copyStatus: OSStatus?
    var adds: [[String: Any]] = []
    var deletes: [String] = []

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
      if let s = copyStatus { return (s, nil) }
      guard query[kSecAttrService as String] as? String == SeatKeyStore.service else {
        return (errSecItemNotFound, nil)
      }
      if let account = query[kSecAttrAccount as String] as? String {
        guard let item = items[account] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, item.data as CFData)
      }
      if items.isEmpty { return (errSecItemNotFound, nil) }
      let list = items.keys.map { [kSecAttrAccount as String: $0] }
      return (errSecSuccess, list as CFArray)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
      adds.append(attributes)
      let account = attributes[kSecAttrAccount as String] as! String
      if items[account] != nil { return errSecDuplicateItem }
      items[account] = (attributes[kSecValueData as String] as! Data, attributes)
      return errSecSuccess
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
      let from = query[kSecAttrAccount as String] as! String
      let to = attributes[kSecAttrAccount as String] as! String
      guard let item = items.removeValue(forKey: from) else { return errSecItemNotFound }
      items[to] = item
      return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
      let account = query[kSecAttrAccount as String] as! String
      deletes.append(account)
      return items.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
    }
  }

  private func store(_ kc: FakeKeychain, _ f: SoftwareFactory) -> SeatKeyStore {
    SeatKeyStore(client: kc, factory: f, accessGroup: nil, sleeper: { _ in })
  }

  private func hex(_ s: String) -> Data {
    var d = Data()
    var i = s.startIndex
    while i < s.endIndex {
      let j = s.index(i, offsetBy: 2)
      d.append(UInt8(s[i..<j], radix: 16)!)
      i = j
    }
    return d
  }

  private func b64url(_ s: String) -> Data {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)!
  }

  // seat-proof-v1.json, vector "restore" (message) and "restore-low-s"
  // (signature). seat_key_service_test.dart checks these constants against
  // the JSON file.
  private let vectorMessageHex =
    "7a6167686c6f6c2d736561742d763100726573746f72650030313933663263342d376131302d346335322d396433652d35623166386132633665373700b086de78734a02cbda6c4f4d0d9c7117a344c7c4cd8126db00236e6552e6ade6"
  private let vectorPublicKey =
    "BKw-hZOelhI7Qqz1u2fvEeenXV7sdJXBqF8DBH1C87-1EVRGa-CMMTOjVMX8Hlomdv0syufgIhH1vIY-jnxNauk"
  private let vectorLowSSignature =
    "hMssrOYuxgIEKASji4runsYFtcZbeW_gPstqad5t2QlsiRMBYBX_PAyGf7fbz4Shdx2PL_UUciNsUf9oW73prg"

  // MARK: Attributes

  func testItemAttributesAreThisDeviceOnlyAndNotSynchronizable() throws {
    let kc = FakeKeychain()
    _ = try store(kc, SoftwareFactory()).publicKeys()
    XCTAssertEqual(kc.adds.count, 1)
    let a = kc.adds[0]
    XCTAssertEqual(a[kSecClass as String] as? String, kSecClassGenericPassword as String)
    XCTAssertEqual(a[kSecAttrService as String] as? String, "app.zaghlol.seatkey")
    XCTAssertEqual(
      a[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(a[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertNil(a[kSecAttrAccessGroup as String])
    // A signed build names only the app's own group, never a shared one.
    let g = SeatKeyStore.addAttributes(account: "own", blob: Data([1]), accessGroup: "ABCDE12345.app.zaghlol")
    XCTAssertEqual(g[kSecAttrAccessGroup as String] as? String, "ABCDE12345.app.zaghlol")
  }

  /// The real Keychain of the test host: the stored item reports the same
  /// protection class and is not synchronizable.
  func testRealKeychainItemHasThisDeviceOnlyProtection() throws {
    let s = SeatKeyStore(client: SystemSeatKeychain(), factory: SoftwareFactory(), sleeper: { _ in })
    let cleanup = SeatKeyStore.itemQuery(account: "own", accessGroup: s.accessGroup)
    SecItemDelete(cleanup as CFDictionary)
    defer { SecItemDelete(cleanup as CFDictionary) }
    do {
      _ = try s.publicKeys()
    } catch {
      throw XCTSkip("no Keychain access in this test host")
    }
    var q = cleanup
    q[kSecReturnAttributes as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &out), errSecSuccess)
    let attrs = out as? [String: Any] ?? [:]
    XCTAssertEqual(
      attrs[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertNotEqual(attrs[kSecAttrSynchronizable as String] as? Bool, true)
  }

  // MARK: Element 0 and rotation

  func testOwnKeyIsStableAcrossLaunches() throws {
    let kc = FakeKeychain()
    let f = SoftwareFactory()
    let first = try store(kc, f).publicKeys()
    let again = try store(kc, f).publicKeys()  // a new launch: new store
    let signed = try store(kc, f).sign(Data("m".utf8))
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(first, again)
    XCTAssertEqual(signed.map { $0.publicKey }, first)
    XCTAssertEqual(f.created, 1)
  }

  func testSixRotationsKeepFiveKeysNewestFirst() throws {
    let kc = FakeKeychain()
    let s = store(kc, SoftwareFactory())
    var owns: [Data] = []
    for _ in 0..<6 {
      owns.append(try s.publicKeys()[0])
      try s.rotateForNewInstall()
    }
    let keys = try s.publicKeys()
    XCTAssertEqual(keys.count, 5)
    XCTAssertFalse(owns.contains(keys[0]), "a new own key after the last rotation")
    XCTAssertEqual(Array(keys[1...]), Array(owns.reversed().prefix(4)))
    XCTAssertEqual(kc.items.count, 5, "FIFO cap deletes the oldest")
  }

  func testRotationMovesTheOwnKeyToElementOne() throws {
    let s = store(FakeKeychain(), SoftwareFactory())
    let before = try s.publicKeys()[0]
    try s.rotateForNewInstall()
    try s.rotateForNewInstall()  // idempotent until a new own key exists
    let after = try s.publicKeys()
    XCTAssertEqual(after.count, 2)
    XCTAssertNotEqual(after[0], before)
    XCTAssertEqual(after[1], before)
  }

  // MARK: Signatures

  func testSignVerifiesWithCryptoKitInTheVectorFormat() throws {
    let message = hex(vectorMessageHex)
    let out = try store(FakeKeychain(), SoftwareFactory()).sign(message)
    XCTAssertEqual(out.count, 1)
    let pk = out[0].publicKey
    XCTAssertEqual(pk.count, 65)
    XCTAssertEqual(pk.first, 0x04)
    XCTAssertEqual(out[0].signature.count, 64)
    let pub = try P256.Signing.PublicKey(x963Representation: pk)
    let sig = try P256.Signing.ECDSASignature(rawRepresentation: out[0].signature)
    XCTAssertTrue(pub.isValidSignature(sig, for: message))
    XCTAssertFalse(pub.isValidSignature(sig, for: message + Data([0])))
  }

  /// The backend's encoding (X9.63 key, P1363 r‖s) is what CryptoKit reads.
  func testVectorProofVerifiesWithCryptoKit() throws {
    let pub = try P256.Signing.PublicKey(x963Representation: b64url(vectorPublicKey))
    let sig = try P256.Signing.ECDSASignature(rawRepresentation: b64url(vectorLowSSignature))
    XCTAssertTrue(pub.isValidSignature(sig, for: hex(vectorMessageHex)))
  }

  // MARK: Unusable keys and errors

  func testUnusableEarlierKeyIsDroppedAndDeleted() throws {
    let kc = FakeKeychain()
    let f = SoftwareFactory()
    let s = store(kc, f)
    let old = try s.publicKeys()[0]
    try s.rotateForNewInstall()
    let own = try s.publicKeys()[0]
    let oldBlob = kc.items["earlier.0000000001"]!.data
    f.failSign.insert(oldBlob)
    let out = try s.sign(Data("m".utf8))
    XCTAssertEqual(out.map { $0.publicKey }, [own])
    XCTAssertNil(kc.items["earlier.0000000001"])
    XCTAssertFalse(try s.publicKeys().contains(old))
  }

  func testUnusableOwnKeyIsReplacedSoElementZeroIsStillOwn() throws {
    let kc = FakeKeychain()
    let f = SoftwareFactory()
    let s = store(kc, f)
    let own = try s.publicKeys()[0]
    f.bad.insert(kc.items["own"]!.data)
    let keys = try s.publicKeys()
    XCTAssertEqual(keys.count, 1)
    XCTAssertNotEqual(keys[0], own)
    XCTAssertNotNil(kc.items["own"])
  }

  /// Self-check §1: a Keychain read error (for example before the first
  /// unlock) is unavailable and never deletes or creates anything.
  func testKeychainErrorDeletesAndCreatesNothing() throws {
    let kc = FakeKeychain()
    let f = SoftwareFactory()
    let s = store(kc, f)
    _ = try s.publicKeys()
    try s.rotateForNewInstall()
    _ = try s.publicKeys()
    let before = kc.items.count
    kc.copyStatus = errSecInteractionNotAllowed
    XCTAssertThrowsError(try s.publicKeys())
    XCTAssertThrowsError(try s.sign(Data("m".utf8)))
    XCTAssertThrowsError(try s.rotateForNewInstall())
    XCTAssertEqual(kc.items.count, before)
    XCTAssertTrue(kc.deletes.isEmpty)
    XCTAssertEqual(f.created, 2)
  }

  func testOtherAccountsUnderTheServiceAreIgnored() throws {
    let kc = FakeKeychain()
    kc.items["t016-dummy"] = (Data([1, 2, 3]), [:])
    kc.items["earlier.12"] = (Data([4]), [:])
    let s = store(kc, SoftwareFactory())
    XCTAssertEqual(try s.publicKeys().count, 1)
    try s.rotateForNewInstall()
    XCTAssertEqual(try s.publicKeys().count, 2)
    XCTAssertNotNil(kc.items["t016-dummy"])
    XCTAssertNotNil(kc.items["earlier.12"])
  }

  func testNoSecureEnclaveReturnsNothingAndTouchesNoKeychain() throws {
    let kc = FakeKeychain()
    let f = SoftwareFactory()
    f.isAvailable = false
    let s = store(kc, f)
    XCTAssertEqual(try s.publicKeys(), [])
    XCTAssertTrue(try s.sign(Data("m".utf8)).isEmpty)
    try s.rotateForNewInstall()
    XCTAssertTrue(kc.adds.isEmpty)
  }

  func testHostErrorsCarryACodeOnly() {
    let kc = FakeKeychain()
    kc.copyStatus = errSecInteractionNotAllowed
    let host = SeatKeyHost(store: store(kc, SoftwareFactory()))
    XCTAssertThrowsError(try host.publicKeys()) { e in
      let err = e as? SeatKeyApiError
      XCTAssertEqual(err?.code, "SEAT_KEY_UNAVAILABLE")
      XCTAssertNil(err?.message)
      XCTAssertNil(err?.details)
    }
  }

  // MARK: Device only (R-19 groundwork; the reinstall run is manual)

  func testSecureEnclaveRoundTripOnDevice() throws {
    guard SecureEnclave.isAvailable else {
      throw XCTSkip("no Secure Enclave (Simulator); run on a device")
    }
    let s = SeatKeyStore(
      client: FakeKeychain(), factory: SecureEnclaveSeatKeyFactory(), accessGroup: nil)
    let message = hex(vectorMessageHex)
    let out = try s.sign(message)
    let pub = try P256.Signing.PublicKey(x963Representation: out[0].publicKey)
    let sig = try P256.Signing.ECDSASignature(rawRepresentation: out[0].signature)
    XCTAssertTrue(pub.isValidSignature(sig, for: message))
    XCTAssertEqual(try s.publicKeys(), [out[0].publicKey])
  }
}
