import DeviceCheck
import Flutter
import Security
import XCTest

@testable import Runner

/// T-178 (platform-channels §4a): R2-1 hash pass-through, the install-bound
/// key lifecycle, the error map and the Keychain item attributes. App Attest
/// runs through a fake (the simulator has no App Attest); one test uses the
/// real Keychain and skips when the unsigned test host has no access. All
/// values are synthetic.
final class AttestationTests: XCTestCase {

  private final class FakeService: AppAttestService {
    var isSupported = true
    var nextKeyIds = ["key-new-1", "key-new-2"]
    var generateKeyError: Error?
    var attestError: Error?
    /// Errors for successive generateAssertion calls (nil = success).
    var assertionErrors: [Error?] = []
    /// Defer generateKey completions (two-actor test).
    var deferGenerateKey = false
    var deferredGenerateKey: [(String?, Error?) -> Void] = []

    var generateKeyCalls = 0
    var attestCalls: [(String, Data)] = []
    var assertionCalls: [(String, Data)] = []

    func generateKey(completion: @escaping (String?, Error?) -> Void) {
      generateKeyCalls += 1
      if deferGenerateKey {
        deferredGenerateKey.append(completion)
        return
      }
      answerGenerateKey(completion)
    }

    func answerGenerateKey(_ completion: (String?, Error?) -> Void) {
      if let e = generateKeyError { return completion(nil, e) }
      completion(nextKeyIds.removeFirst(), nil)
    }

    func attestKey(_ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void) {
      attestCalls.append((keyId, clientDataHash))
      if let e = attestError { return completion(nil, e) }
      completion(Data("attestation-object:\(keyId)".utf8), nil)
    }

    func generateAssertion(
      _ keyId: String, clientDataHash: Data, completion: @escaping (Data?, Error?) -> Void
    ) {
      assertionCalls.append((keyId, clientDataHash))
      let e = assertionErrors.isEmpty ? nil : assertionErrors.removeFirst()
      if let e = e { return completion(nil, e) }
      completion(Data("assertion:\(keyId)".utf8), nil)
    }
  }

  private final class FakeStore: AttestKeyIdStore {
    var stored: String?
    var readResult: AttestKeyIdRead?
    var replaceOk = true
    var replaced: [String] = []

    func read() -> AttestKeyIdRead {
      if let r = readResult { return r }
      return stored.map { .found($0) } ?? .notFound
    }

    func replace(_ keyId: String) -> Bool {
      replaced.append(keyId)
      guard replaceOk else { return false }
      stored = keyId
      readResult = nil
      return true
    }
  }

  private func hash(_ seed: Int = 7) -> Data {
    Data((0..<32).map { UInt8((seed + 31 * $0) & 0xFF) })
  }

  private func dc(_ code: DCError.Code) -> Error {
    NSError(domain: DCErrorDomain, code: code.rawValue)
  }

  private func makeHost(_ service: FakeService, _ store: FakeStore) -> AttestationHost {
    AttestationHost(service: service, store: store, hop: { $0() })
  }

  private func attest(_ host: AttestationHost, _ hash: Data, force: Bool = false)
    -> Result<AttestationProof, Error>?
  {
    var out: Result<AttestationProof, Error>?
    host.attest(bodyHash: FlutterStandardTypedData(bytes: hash), forceNewKey: force) { out = $0 }
    return out
  }

  private func code(_ result: Result<AttestationProof, Error>?) -> String? {
    guard case .failure(let e)? = result, let api = e as? AttestationApiError else { return nil }
    // Code only: no SDK text, hash, token or key ID crosses the boundary.
    XCTAssertNil(api.message)
    XCTAssertNil(api.details)
    return api.code
  }

  private func proof(_ result: Result<AttestationProof, Error>?) -> AttestationProof? {
    guard case .success(let p)? = result else { return nil }
    return p
  }

  // MARK: R2-1 / R4-1(3): the exact Dart bytes, same hash for attestKey and assertion

  /// clientDataHashHex of the `ios-member-order` vector (restore-binding-v1.json).
  private let vectorClientDataHash = Data(
    stride(from: 0, to: 64, by: 2).map { i -> UInt8 in
      let hex = "61919458bfe2397960031bf51653e610d5a05c35c69651126b36ea14db329d33"
      let s = hex.index(hex.startIndex, offsetBy: i)
      return UInt8(hex[s..<hex.index(s, offsetBy: 2)], radix: 16)!
    })

  func testNewKeyAttestsAndAssertsTheExactInputBytes() throws {
    let service = FakeService()
    let store = FakeStore()
    let p = try XCTUnwrap(proof(attest(makeHost(service, store), vectorClientDataHash)))

    XCTAssertEqual(service.attestCalls.count, 1)
    XCTAssertEqual(service.assertionCalls.count, 1)
    XCTAssertEqual(service.attestCalls[0].1, vectorClientDataHash)
    XCTAssertEqual(service.assertionCalls[0].1, vectorClientDataHash)
    XCTAssertEqual(service.attestCalls[0].0, "key-new-1")
    XCTAssertEqual(service.assertionCalls[0].0, "key-new-1")
    XCTAssertEqual(p.type, "app_attest")
    XCTAssertNil(p.token)
    XCTAssertEqual(p.keyId, "key-new-1")
    XCTAssertEqual(p.assertion, Data("assertion:key-new-1".utf8).base64EncodedString())
    XCTAssertEqual(p.attestationObject, Data("attestation-object:key-new-1".utf8).base64EncodedString())
    XCTAssertEqual(store.stored, "key-new-1")
  }

  func testStoredKeyAssertsWithTheExactInputAndNoAttestation() throws {
    let service = FakeService()
    let store = FakeStore()
    store.stored = "key-old"
    let input = hash(3)
    let p = try XCTUnwrap(proof(attest(makeHost(service, store), input)))
    XCTAssertEqual(service.generateKeyCalls, 0)
    XCTAssertTrue(service.attestCalls.isEmpty)
    XCTAssertEqual(service.assertionCalls.map { $0.0 }, ["key-old"])
    XCTAssertEqual(service.assertionCalls[0].1, input)
    XCTAssertEqual(p.keyId, "key-old")
    XCTAssertNil(p.attestationObject)
    XCTAssertTrue(store.replaced.isEmpty)
  }

  // MARK: Key replacement

  func testForceNewKeyReplacesTheStoredKeyAndReturnsAttestation() throws {
    let service = FakeService()
    let store = FakeStore()
    store.stored = "key-old"
    let input = hash(5)
    let p = try XCTUnwrap(proof(attest(makeHost(service, store), input, force: true)))
    XCTAssertEqual(store.stored, "key-new-1")
    XCTAssertEqual(p.keyId, "key-new-1")
    XCTAssertNotNil(p.attestationObject)
    XCTAssertEqual(service.attestCalls[0].1, input)
    XCTAssertEqual(service.assertionCalls.map { $0.0 }, ["key-new-1"])
    XCTAssertEqual(service.assertionCalls[0].1, input)
  }

  func testInvalidKeyReplacesTheStoredKeyAndReturnsAttestation() throws {
    let service = FakeService()
    service.assertionErrors = [dc(.invalidKey)]
    let store = FakeStore()
    store.stored = "key-old"
    let input = hash(9)
    let p = try XCTUnwrap(proof(attest(makeHost(service, store), input)))
    XCTAssertEqual(service.assertionCalls.map { $0.0 }, ["key-old", "key-new-1"])
    XCTAssertTrue(service.assertionCalls.allSatisfy { $0.1 == input })
    XCTAssertEqual(service.attestCalls.map { $0.1 }, [input])
    XCTAssertEqual(store.stored, "key-new-1")
    XCTAssertEqual(p.keyId, "key-new-1")
    XCTAssertNotNil(p.attestationObject)
  }

  func testInvalidKeyOnAFreshKeyIsUnavailableWithoutLooping() {
    let service = FakeService()
    service.assertionErrors = [dc(.invalidKey), dc(.invalidKey), nil]
    let store = FakeStore()
    store.stored = "key-old"
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_UNAVAILABLE")
    XCTAssertEqual(service.generateKeyCalls, 1)
  }

  // Self-check §1: never a new key on doubt.
  func testUnreadableKeychainNeverMakesANewKey() {
    let service = FakeService()
    let store = FakeStore()
    store.readResult = .unavailable
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_UNAVAILABLE")
    XCTAssertEqual(service.generateKeyCalls, 0)
    XCTAssertTrue(store.replaced.isEmpty)
  }

  func testOldKeyIdStaysWhenTheNewKeyCannotBeAttested() {
    for err in [dc(.serverUnavailable), dc(.unknownSystemFailure)] {
      let service = FakeService()
      service.attestError = err
      let store = FakeStore()
      store.stored = "key-old"
      XCTAssertNotNil(code(attest(makeHost(service, store), hash(), force: true)))
      XCTAssertEqual(store.stored, "key-old")
      XCTAssertTrue(store.replaced.isEmpty)
    }
  }

  func testAFailedKeychainWriteReturnsNoProof() {
    let service = FakeService()
    let store = FakeStore()
    store.replaceOk = false
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_UNAVAILABLE")
    XCTAssertTrue(service.assertionCalls.isEmpty)
  }

  // Two actors: a second restore while the first is creating the key waits and reuses it.
  func testConcurrentCallsCreateOneKey() throws {
    let service = FakeService()
    service.deferGenerateKey = true
    let store = FakeStore()
    let host = makeHost(service, store)
    var results: [Result<AttestationProof, Error>] = []
    host.attest(bodyHash: FlutterStandardTypedData(bytes: hash(1)), forceNewKey: false) { results.append($0) }
    host.attest(bodyHash: FlutterStandardTypedData(bytes: hash(2)), forceNewKey: false) { results.append($0) }
    XCTAssertEqual(service.generateKeyCalls, 1)
    XCTAssertTrue(results.isEmpty)
    service.answerGenerateKey(service.deferredGenerateKey.removeFirst())
    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(service.generateKeyCalls, 1)
    XCTAssertEqual(try XCTUnwrap(proof(results[0])).keyId, "key-new-1")
    XCTAssertNotNil(try XCTUnwrap(proof(results[0])).attestationObject)
    XCTAssertEqual(try XCTUnwrap(proof(results[1])).keyId, "key-new-1")
    XCTAssertNil(try XCTUnwrap(proof(results[1])).attestationObject)
    XCTAssertEqual(service.assertionCalls.map { $0.1 }, [hash(1), hash(2)])
  }

  // MARK: Error map

  func testErrorMap() {
    XCTAssertEqual(AttestationHost.code(for: dc(.serverUnavailable)), "ATTEST_TRANSIENT")
    for c: DCError.Code in [.unknownSystemFailure, .featureUnsupported, .invalidInput, .invalidKey] {
      XCTAssertEqual(AttestationHost.code(for: dc(c)), "ATTEST_UNAVAILABLE")
    }
    XCTAssertEqual(
      AttestationHost.code(for: NSError(domain: NSURLErrorDomain, code: DCError.Code.serverUnavailable.rawValue)),
      "ATTEST_UNAVAILABLE")
    XCTAssertEqual(AttestationHost.code(for: nil), "ATTEST_UNAVAILABLE")
  }

  func testServerUnavailableIsTransientAtEveryStep() {
    // assertion with a stored key
    var service = FakeService()
    service.assertionErrors = [dc(.serverUnavailable)]
    var store = FakeStore()
    store.stored = "key-old"
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_TRANSIENT")
    XCTAssertEqual(service.generateKeyCalls, 0)
    // generateKey
    service = FakeService()
    service.generateKeyError = dc(.serverUnavailable)
    store = FakeStore()
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_TRANSIENT")
    // attestKey
    service = FakeService()
    service.attestError = dc(.serverUnavailable)
    XCTAssertEqual(code(attest(makeHost(service, FakeStore()), hash())), "ATTEST_TRANSIENT")
  }

  func testUnsupportedDeviceIsUnavailable() {
    let service = FakeService()
    service.isSupported = false
    let store = FakeStore()
    store.stored = "key-old"
    XCTAssertEqual(code(attest(makeHost(service, store), hash())), "ATTEST_UNAVAILABLE")
    XCTAssertEqual(code(attest(makeHost(service, store), hash(), force: true)), "ATTEST_UNAVAILABLE")
    XCTAssertEqual(service.generateKeyCalls, 0)
    XCTAssertTrue(service.assertionCalls.isEmpty)
  }

  func testWrongLengthHashIsRefusedWithoutCallingAppAttest() {
    for n in [0, 31, 33, 64] {
      let service = FakeService()
      XCTAssertEqual(
        code(attest(makeHost(service, FakeStore()), Data(repeating: 1, count: n))), "ATTEST_UNAVAILABLE")
      XCTAssertEqual(service.generateKeyCalls, 0)
      XCTAssertTrue(service.assertionCalls.isEmpty)
    }
  }

  func testPrepareIsANoOp() {
    var ok = false
    makeHost(FakeService(), FakeStore()).prepare { if case .success = $0 { ok = true } }
    XCTAssertTrue(ok)
  }

  // MARK: Keychain store

  private final class FakeKeychain: KeychainClient {
    var item: Data?
    var copyStatus: OSStatus?
    var adds: [[String: Any]] = []
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
      if let s = copyStatus { return (s, nil) }
      return item.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
      adds.append(attributes)
      item = attributes[kSecValueData as String] as? Data
      return errSecSuccess
    }
    func delete(_ query: [String: Any]) -> OSStatus {
      if item == nil { return errSecItemNotFound }
      item = nil
      return errSecSuccess
    }
  }

  func testKeyIdItemAttributes() {
    let attrs = KeychainAttestKeyIdStore.addAttributes(keyId: "k", accessGroup: nil)
    XCTAssertEqual(
      attrs[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(attrs[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertEqual(attrs[kSecAttrService as String] as? String, "app.zaghlol.attest")
    XCTAssertEqual(attrs[kSecAttrAccount as String] as? String, "app_attest_key_id_v1")
    XCTAssertEqual(
      KeychainAttestKeyIdStore.addAttributes(keyId: "k", accessGroup: "ABCDE12345.app.zaghlol.dev")[
        kSecAttrAccessGroup as String] as? String,
      "ABCDE12345.app.zaghlol.dev")
  }

  func testKeychainReadClassification() {
    let kc = FakeKeychain()
    let store = KeychainAttestKeyIdStore(client: kc, accessGroup: nil)
    XCTAssertEqual(store.read(), .notFound)
    XCTAssertTrue(store.replace("key-a"))
    XCTAssertEqual(store.read(), .found("key-a"))
    XCTAssertTrue(store.replace("key-b"))
    XCTAssertEqual(store.read(), .found("key-b"))
    kc.item = Data()
    XCTAssertEqual(store.read(), .notFound)
    for s: OSStatus in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecIO, -1] {
      kc.copyStatus = s
      XCTAssertEqual(store.read(), .unavailable, "status \(s)")
    }
  }

  func testRealKeychainItemAttributes() throws {
    let store = KeychainAttestKeyIdStore()
    let q = KeychainAttestKeyIdStore.itemQuery(accessGroup: store.accessGroup)
    SecItemDelete(q as CFDictionary)
    guard store.read() == .notFound else {
      throw XCTSkip("no Keychain access in this test host")
    }
    defer { SecItemDelete(q as CFDictionary) }
    XCTAssertTrue(store.replace("synthetic-key-id"))
    XCTAssertEqual(store.read(), .found("synthetic-key-id"))

    var aq = q
    aq[kSecReturnAttributes as String] = kCFBooleanTrue
    aq[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(aq as CFDictionary, &out), errSecSuccess)
    let attrs = out as? [String: Any]
    XCTAssertEqual(
      attrs?[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual((attrs?[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false, false)
  }
}
