import Flutter
import Security
import XCTest

@testable import Runner

/// T-015 (design note §2, §9): Keychain item attributes, OSStatus mapping,
/// create/read/delete semantics, the bootstrap lease and the host's code-only
/// errors. Keychain calls go through a fake; one test touches the real
/// Keychain and skips when the unsigned test host has no Keychain access.
final class SecretStoreTests: XCTestCase {

  /// A synthetic key: never a real key, never printed.
  private func syntheticKey(_ seed: Int = 61) -> Data {
    Data((0..<32).map { UInt8((seed + 97 * $0) & 0xFF) })
  }

  private final class FakeKeychain: KeychainClient {
    var item: Data?
    var copyStatus: OSStatus?
    var addStatus: OSStatus?
    var deleteStatus: OSStatus?
    var adds: [[String: Any]] = []
    var deletes: [[String: Any]] = []
    var queries: [[String: Any]] = []

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
      queries.append(query)
      if let s = copyStatus { return (s, nil) }
      guard let item = item else { return (errSecItemNotFound, nil) }
      return (errSecSuccess, item)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
      adds.append(attributes)
      if let s = addStatus { return s }
      if item != nil { return errSecDuplicateItem }
      item = attributes[kSecValueData as String] as? Data
      return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
      deletes.append(query)
      if let s = deleteStatus { return s }
      if item == nil { return errSecItemNotFound }
      item = nil
      return errSecSuccess
    }
  }

  private var sleeps: [UInt32] = []

  private static let ownGroup = "ABCDE12345.app.zaghlol.dev"

  private func makeStore(_ keychain: KeychainClient) -> DbKeyKeychain {
    DbKeyKeychain(
      client: keychain, accessGroup: SecretStoreTests.ownGroup,
      sleeper: { self.sleeps.append($0) })
  }

  override func setUp() {
    sleeps = []
  }

  // MARK: Attributes

  func testItemIsAfterFirstUnlockThisDeviceOnlyAndNotSynchronizable() {
    let attrs = DbKeyKeychain.addAttributes(value: syntheticKey(), accessGroup: nil)
    XCTAssertEqual(
      attrs[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(attrs[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertEqual(attrs[kSecClass as String] as? String, kSecClassGenericPassword as String)
    XCTAssertEqual(attrs[kSecAttrService as String] as? String, "app.zaghlol.keys")
    XCTAssertEqual(attrs[kSecAttrAccount as String] as? String, "db_key_v1")
    XCTAssertNil(attrs[kSecAttrAccessGroup as String], "unsigned build: no group to name")
  }

  // S-3: K_db is pinned to Runner's own application-identifier group.

  func testAccessGroupIsResolvedFromThePrefixAndBundleId() {
    XCTAssertEqual(
      DbKeyKeychain.resolveAccessGroup(prefix: "ABCDE12345.", bundleId: "app.zaghlol"),
      "ABCDE12345.app.zaghlol")
    XCTAssertEqual(
      DbKeyKeychain.resolveAccessGroup(prefix: "ABCDE12345", bundleId: "app.zaghlol.dev"),
      "ABCDE12345.app.zaghlol.dev")
    for prefix: String? in [nil, "", "$(AppIdentifierPrefix)"] {
      XCTAssertNil(DbKeyKeychain.resolveAccessGroup(prefix: prefix, bundleId: "app.zaghlol"))
    }
    XCTAssertNil(DbKeyKeychain.resolveAccessGroup(prefix: "ABCDE12345.", bundleId: nil))
    XCTAssertNil(DbKeyKeychain.resolveAccessGroup(prefix: "ABCDE12345.", bundleId: ""))
  }

  func testTheDefaultStoreUsesTheAppsOwnGroup() {
    XCTAssertEqual(DbKeyKeychain().accessGroup, DbKeyKeychain.appAccessGroup)
    if let group = DbKeyKeychain.appAccessGroup {
      XCTAssertTrue(group.hasSuffix("." + (Bundle.main.bundleIdentifier ?? "-")))
    }
  }

  func testEveryCallNamesTheOwnAccessGroup() throws {
    let kc = FakeKeychain()
    let store = makeStore(kc)
    _ = store.read()
    _ = try store.createIfAbsent(syntheticKey())
    _ = store.read()
    try store.delete()
    XCTAssertFalse(kc.queries.isEmpty)
    XCTAssertEqual(kc.adds.count, 1)
    XCTAssertEqual(kc.deletes.count, 1)
    for q in kc.queries + kc.adds + kc.deletes {
      XCTAssertEqual(q[kSecAttrAccessGroup as String] as? String, SecretStoreTests.ownGroup)
    }
  }

  func testEveryQueryNamesServiceAndAccount() {
    let g = SecretStoreTests.ownGroup
    for q in [DbKeyKeychain.itemQuery(accessGroup: g), DbKeyKeychain.readQuery(accessGroup: g)] {
      XCTAssertEqual(q[kSecAttrService as String] as? String, "app.zaghlol.keys")
      XCTAssertEqual(q[kSecAttrAccount as String] as? String, "db_key_v1")
      XCTAssertEqual(q[kSecAttrSynchronizable as String] as? Bool, false)
    }
  }

  // MARK: OSStatus mapping

  func testStatusMapping() {
    XCTAssertEqual(DbKeyKeychain.classify(status: errSecSuccess, data: syntheticKey()).status, .found)
    XCTAssertEqual(DbKeyKeychain.classify(status: errSecSuccess, data: Data(count: 16)).status, .unusable)
    XCTAssertEqual(DbKeyKeychain.classify(status: errSecSuccess, data: nil).status, .unavailable)
    XCTAssertEqual(DbKeyKeychain.classify(status: errSecItemNotFound, data: nil).status, .notFound)
    XCTAssertEqual(
      DbKeyKeychain.classify(status: errSecInteractionNotAllowed, data: nil).status, .unavailable)
    for other: OSStatus in [errSecMissingEntitlement, errSecAuthFailed, errSecIO, errSecParam, -1, 1] {
      XCTAssertEqual(DbKeyKeychain.classify(status: other, data: nil).status, .unavailable)
    }
  }

  // MARK: Store semantics

  func testCreateThenReadReturnsTheSameKey() throws {
    let kc = FakeKeychain()
    let store = makeStore(kc)
    XCTAssertEqual(store.read().status, .notFound)
    let stored = try store.createIfAbsent(syntheticKey())
    XCTAssertEqual(stored, syntheticKey())
    let r = store.read()
    XCTAssertEqual(r.status, .found)
    XCTAssertEqual(r.value, syntheticKey())
    XCTAssertEqual(kc.adds.count, 1)
  }

  func testExistingKeyWinsOverANewCandidate() throws {
    let kc = FakeKeychain()
    kc.item = syntheticKey(1)
    let winner = try makeStore(kc).createIfAbsent(syntheticKey(2))
    XCTAssertEqual(winner, syntheticKey(1))
    XCTAssertTrue(kc.adds.isEmpty)
  }

  func testDuplicateOnAddReturnsTheWinner() throws {
    // The first read sees nothing; the add then races with another writer.
    let raced = DbKeyKeychain(
      client: RaceKeychain(winner: syntheticKey(3)), accessGroup: nil, sleeper: { _ in })
    XCTAssertEqual(try raced.createIfAbsent(syntheticKey(4)), syntheticKey(3))
  }

  private final class RaceKeychain: KeychainClient {
    let winner: Data
    var added = false
    init(winner: Data) { self.winner = winner }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
      added ? (errSecSuccess, winner) : (errSecItemNotFound, nil)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
      added = true
      return errSecDuplicateItem
    }
    func delete(_ query: [String: Any]) -> OSStatus { errSecSuccess }
  }

  func testUnavailableIsRetriedThenReported() {
    let kc = FakeKeychain()
    kc.copyStatus = errSecInteractionNotAllowed
    let r = makeStore(kc).read()
    XCTAssertEqual(r.status, .unavailable)
    XCTAssertNil(r.value)
    XCTAssertEqual(r.attempts, 4)
    XCTAssertEqual(sleeps, [100, 300, 900])
  }

  // S-1: one bad observation is not proof; every attempt must agree.

  /// Returns the scripted statuses in order, then repeats the last one.
  private final class ScriptedKeychain: KeychainClient {
    var script: [(OSStatus, Data?)]
    var reads = 0
    init(_ script: [(OSStatus, Data?)]) { self.script = script }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
      defer { reads += 1 }
      return script[min(reads, script.count - 1)]
    }
    func add(_ attributes: [String: Any]) -> OSStatus { errSecIO }
    func delete(_ query: [String: Any]) -> OSStatus { errSecSuccess }
  }

  func testOneNotFoundThenSuccessReturnsTheKey() {
    let kc = ScriptedKeychain([(errSecItemNotFound, nil), (errSecSuccess, syntheticKey())])
    let r = makeStore(kc).read()
    XCTAssertEqual(r.status, .found)
    XCTAssertEqual(r.value, syntheticKey())
    XCTAssertEqual(r.attempts, 2)
    XCTAssertEqual(sleeps, [100])
  }

  func testNotFoundOnEveryAttemptIsNotFound() {
    let kc = FakeKeychain()
    let r = makeStore(kc).read()
    XCTAssertEqual(r.status, .notFound)
    XCTAssertEqual(r.attempts, 4)
    XCTAssertEqual(sleeps, [100, 300, 900])
  }

  func testOneWrongLengthThenSuccessReturnsTheKey() {
    let kc = ScriptedKeychain([
      (errSecSuccess, Data(count: 16)), (errSecSuccess, Data(count: 16)),
      (errSecSuccess, Data(count: 16)), (errSecSuccess, syntheticKey()),
    ])
    let r = makeStore(kc).read()
    XCTAssertEqual(r.status, .found)
    XCTAssertEqual(r.attempts, 4)
  }

  func testWrongLengthOnEveryAttemptIsUnusable() {
    let r = makeStore(ScriptedKeychain([(errSecSuccess, Data(count: 16))])).read()
    XCTAssertEqual(r.status, .unusable)
    XCTAssertEqual(r.attempts, 4)
  }

  func testDisagreeingAttemptsAreUnavailable() {
    let kc = ScriptedKeychain([
      (errSecItemNotFound, nil), (errSecInteractionNotAllowed, nil), (errSecItemNotFound, nil),
    ])
    let r = makeStore(kc).read()
    XCTAssertEqual(r.status, .unavailable)
    XCTAssertNil(r.value)
    XCTAssertEqual(r.attempts, 4)
  }

  func testCreateRefusesWhileTheStateIsUnknownOrUnusable() {
    let kc = FakeKeychain()
    kc.copyStatus = errSecInteractionNotAllowed
    XCTAssertThrowsError(try makeStore(kc).createIfAbsent(syntheticKey()))
    kc.copyStatus = nil
    kc.item = Data(count: 16)
    XCTAssertThrowsError(try makeStore(kc).createIfAbsent(syntheticKey()))
    XCTAssertTrue(kc.adds.isEmpty)
    XCTAssertTrue(kc.deletes.isEmpty)
  }

  func testDegenerateCandidatesAreRefused() {
    let kc = FakeKeychain()
    for bad in [Data(repeating: 7, count: 32), Data(count: 31), Data()] {
      XCTAssertThrowsError(try makeStore(kc).createIfAbsent(bad))
    }
    XCTAssertTrue(kc.adds.isEmpty)
  }

  func testFailedAddIsKeyStoreFailure() {
    let kc = FakeKeychain()
    kc.addStatus = errSecIO
    XCTAssertThrowsError(try makeStore(kc).createIfAbsent(syntheticKey()))
  }

  func testDeleteIsScopedAndIdempotent() throws {
    let kc = FakeKeychain()
    kc.item = syntheticKey()
    let store = makeStore(kc)
    try store.delete()
    try store.delete()
    XCTAssertEqual(kc.deletes.count, 2)
    for q in kc.deletes {
      XCTAssertEqual(q[kSecAttrService as String] as? String, "app.zaghlol.keys")
      XCTAssertEqual(q[kSecAttrAccount as String] as? String, "db_key_v1")
    }
    kc.deleteStatus = errSecIO
    XCTAssertThrowsError(try store.delete())
  }

  // MARK: Lease

  func testLeaseIsExclusiveUntilReleasedOrExpired() {
    var now: UInt64 = 1_000
    let leases = BootstrapLeaseManager(ttlNanos: 30_000_000_000, clock: { now })
    let first = leases.acquire(timeoutMs: 10)
    XCTAssertNotNil(first)
    XCTAssertTrue(leases.isValid(first!))
    now += 30_000_000_000
    XCTAssertFalse(leases.isValid(first!))
    let second = leases.acquire(timeoutMs: 10)
    XCTAssertNotNil(second)
    leases.release(first!)
    XCTAssertTrue(leases.isValid(second!))
    leases.release(second!)
    XCTAssertFalse(leases.isValid(second!))
  }

  func testLeaseTimesOutWhileHeld() {
    let leases = BootstrapLeaseManager()
    let first = leases.acquire(timeoutMs: 10)
    XCTAssertNotNil(first)
    XCTAssertNil(leases.acquire(timeoutMs: 50))
  }

  // T-016 (S-2, FU-065): renew extends a current lease and never takes one.

  func testRenewExtendsAValidLease() {
    var now: UInt64 = 1_000
    let leases = BootstrapLeaseManager(ttlNanos: 30_000_000_000, clock: { now })
    let lease = leases.acquire(timeoutMs: 10)!
    now += 29_000_000_000
    XCTAssertTrue(leases.renew(lease))
    // Without the renewal the lease would have expired at 30 s.
    now += 29_000_000_000
    XCTAssertTrue(leases.isValid(lease))
    now += 1_000_000_000
    XCTAssertFalse(leases.isValid(lease))
  }

  func testRenewOfAnExpiredLeaseIsFalseAndDoesNotRevive() {
    var now: UInt64 = 1_000
    let leases = BootstrapLeaseManager(ttlNanos: 30_000_000_000, clock: { now })
    let lease = leases.acquire(timeoutMs: 10)!
    now += 30_000_000_000
    XCTAssertFalse(leases.renew(lease))
    XCTAssertFalse(leases.isValid(lease))
    let next = leases.acquire(timeoutMs: 10)
    XCTAssertNotNil(next)
    XCTAssertNotEqual(next, lease)
  }

  func testRenewOfAStaleIdIsFalseAndLeavesTheCurrentLeaseAlone() {
    var now: UInt64 = 1_000
    let leases = BootstrapLeaseManager(ttlNanos: 30_000_000_000, clock: { now })
    let first = leases.acquire(timeoutMs: 10)!
    now += 31_000_000_000
    let second = leases.acquire(timeoutMs: 10)!
    now += 20_000_000_000
    XCTAssertFalse(leases.renew(first))
    XCTAssertFalse(leases.renew(0))
    XCTAssertFalse(leases.renew(-1))
    now += 10_000_000_000
    XCTAssertFalse(leases.isValid(second), "a stale renewal must not extend the current lease")
  }

  func testRenewAfterReleaseIsFalseAndNeverTakesTheLease() {
    let leases = BootstrapLeaseManager()
    let lease = leases.acquire(timeoutMs: 10)!
    leases.release(lease)
    XCTAssertFalse(leases.renew(lease))
    XCTAssertFalse(leases.isValid(lease))
    XCTAssertNotNil(leases.acquire(timeoutMs: 0))
  }

  // MARK: Host errors

  private final class FakeSlot: SecretSlotStore {
    var fail = false
    func read() -> SlotRead { SlotRead(status: .notFound, value: nil, attempts: 1) }
    func createIfAbsent(_ candidate: Data) throws -> Data {
      if fail { throw NSError(domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "detail"]) }
      return candidate
    }
    func delete() throws { if fail { throw KeyStoreFailure() } }
  }

  private func syncHost(_ slot: FakeSlot, _ leases: BootstrapLeaseManager) -> SecretStoreHost {
    SecretStoreHost(slots: { _ in slot }, leases: leases, worker: { $0() }, main: { $0() })
  }

  private func assertCodeOnly<T>(_ result: Result<T, Error>?, _ code: String) {
    guard case .failure(let error)? = result, let e = error as? SecretStoreApiError else {
      return XCTFail("expected a SecretStoreApiError")
    }
    XCTAssertEqual(e.code, code)
    XCTAssertNil(e.message)
    XCTAssertNil(e.details)
  }

  func testHostErrorsCarryACodeOnly() {
    let slot = FakeSlot()
    let leases = BootstrapLeaseManager()
    let host = syncHost(slot, leases)
    var created: Result<FlutterStandardTypedData, Error>?
    host.createIfAbsent(
      lease: 42, slot: .dbKey, candidate: FlutterStandardTypedData(bytes: syntheticKey())
    ) { created = $0 }
    assertCodeOnly(created, "LEASE_TIMEOUT")

    var lease: Int64 = 0
    host.acquireBootstrapLease(timeoutMs: 10) { if case .success(let l) = $0 { lease = l } }
    XCTAssertGreaterThan(lease, 0)
    slot.fail = true
    host.createIfAbsent(
      lease: lease, slot: .dbKey, candidate: FlutterStandardTypedData(bytes: syntheticKey())
    ) { created = $0 }
    assertCodeOnly(created, "KEY_STORE_FAILED")
    var deleted: Result<Void, Error>?
    host.delete(lease: lease, slot: .dbKey) { deleted = $0 }
    assertCodeOnly(deleted, "KEY_STORE_FAILED")

    var timedOut: Result<Int64, Error>?
    host.acquireBootstrapLease(timeoutMs: 20) { timedOut = $0 }
    assertCodeOnly(timedOut, "LEASE_TIMEOUT")
  }

  // T-016: renew through the host answers true only for the current lease.
  func testHostRenewIsTrueForTheCurrentLeaseOnly() {
    let leases = BootstrapLeaseManager()
    let host = syncHost(FakeSlot(), leases)
    var lease: Int64 = 0
    host.acquireBootstrapLease(timeoutMs: 10) { if case .success(let l) = $0 { lease = l } }
    XCTAssertGreaterThan(lease, 0)
    var renewed: Bool?
    host.renewBootstrapLease(lease: lease) { if case .success(let v) = $0 { renewed = v } }
    XCTAssertEqual(renewed, true)
    host.renewBootstrapLease(lease: lease + 1) { if case .success(let v) = $0 { renewed = v } }
    XCTAssertEqual(renewed, false)
    host.releaseBootstrapLease(lease: lease) { _ in }
    host.renewBootstrapLease(lease: lease) { if case .success(let v) = $0 { renewed = v } }
    XCTAssertEqual(renewed, false)
  }

  // MARK: Real Keychain (skipped when the unsigned host has no access)

  func testRealKeychainRoundTripAndAttributes() throws {
    let store = DbKeyKeychain(sleeper: { _ in })
    try? store.delete()
    let probe = store.read()
    if probe.status == .unavailable {
      throw XCTSkip("no Keychain access in this test host")
    }
    defer { try? store.delete() }
    XCTAssertEqual(probe.status, .notFound)
    XCTAssertEqual(try store.createIfAbsent(syntheticKey()), syntheticKey())
    XCTAssertEqual(store.read().value, syntheticKey())

    var q = DbKeyKeychain.itemQuery(accessGroup: store.accessGroup)
    q[kSecReturnAttributes as String] = kCFBooleanTrue
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    XCTAssertEqual(SecItemCopyMatching(q as CFDictionary, &out), errSecSuccess)
    let attrs = out as? [String: Any]
    XCTAssertEqual(
      attrs?[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual((attrs?[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false, false)
    if let group = store.accessGroup {
      XCTAssertEqual(attrs?[kSecAttrAccessGroup as String] as? String, group)
    }
  }

  // T-016 (D-50, T-165 F6): deleting the database key (the only secret the
  // orphan wipe deletes) leaves a D-62 seat-key item alone. A dummy item is
  // planted under the seat-key service (platform-channels §4b).
  func testDeletingTheDbKeyLeavesSeatKeyItemsAlone() throws {
    let store = DbKeyKeychain(sleeper: { _ in })
    if store.read().status == .unavailable {
      throw XCTSkip("no Keychain access in this test host")
    }
    var seat: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.zaghlol.seatkey",
      kSecAttrAccount as String: "t016-dummy",
    ]
    if let group = store.accessGroup { seat[kSecAttrAccessGroup as String] = group }
    SecItemDelete(seat as CFDictionary)
    var add = seat
    add[kSecValueData as String] = Data([1, 2, 3])
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
    defer { SecItemDelete(seat as CFDictionary) }

    _ = try store.createIfAbsent(syntheticKey())
    try store.delete()
    XCTAssertEqual(store.read().status, .notFound)
    XCTAssertEqual(SecItemCopyMatching(seat as CFDictionary, nil), errSecSuccess)
  }
}
