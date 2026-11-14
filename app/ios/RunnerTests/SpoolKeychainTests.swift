import Security
import XCTest

@testable import Runner

/// T-062: the Keychain spool key (platform-channels.md 1.3): item attributes,
/// OSStatus classification, the concurrent-create race and the shared groups.
final class SpoolKeychainTests: XCTestCase {

  private final class FakeKeychain: SpoolKeychainClient {
    var item: [String: Any]?
    var copyStatus: OSStatus?
    var addStatus: OSStatus?
    var adds: [[String: Any]] = []
    var deletes: [[String: Any]] = []
    var reads = 0
    /// Simulates the other process winning a create race.
    var winnerOnDuplicate: Data?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, [String: Any]?) {
      reads += 1
      if let s = copyStatus { return (s, nil) }
      guard let item = item else { return (errSecItemNotFound, nil) }
      return (errSecSuccess, item)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
      adds.append(attributes)
      if let s = addStatus {
        if s == errSecDuplicateItem, let w = winnerOnDuplicate {
          item = [kSecValueData as String: w]
        }
        return s
      }
      item = [
        kSecValueData as String: attributes[kSecValueData as String] as Any,
        kSecAttrCreationDate as String: Date(),
      ]
      return errSecSuccess
    }
    func delete(_ query: [String: Any]) -> OSStatus {
      deletes.append(query)
      item = nil
      return errSecSuccess
    }
  }

  private let group = "TEAM123.app.zaghlol.dev.shared"

  private func keychain(_ fake: FakeKeychain, delays: [UInt32] = [1, 1, 1]) -> SpoolKeychain {
    SpoolKeychain(client: fake, accessGroup: group, retryDelaysMs: delays, sleeper: { _ in })
  }

  func testNewKeyHasThe32ByteAfterFirstUnlockThisDeviceOnlyShapeInTheSharedGroup() throws {
    let fake = FakeKeychain()
    let loaded = try keychain(fake).loadOrCreate()
    XCTAssertEqual(loaded.key.count, 32)
    XCTAssertNotNil(loaded.createdAtMs)
    let add = try XCTUnwrap(fake.adds.first)
    XCTAssertEqual(add[kSecClass as String] as? String, kSecClassGenericPassword as String)
    XCTAssertEqual(add[kSecAttrService as String] as? String, "app.zaghlol.spool")
    XCTAssertEqual(add[kSecAttrAccount as String] as? String, "spool_key_v1")
    XCTAssertEqual(add[kSecAttrAccessGroup as String] as? String, group)
    XCTAssertEqual(
      add[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertEqual((add[kSecValueData as String] as? Data)?.count, 32)
  }

  func testExistingKeyIsReadNotReplaced() throws {
    let fake = FakeKeychain()
    let first = try keychain(fake).loadOrCreate()
    let second = try keychain(fake).loadOrCreate()
    XCTAssertEqual(first.key, second.key)
    XCTAssertEqual(fake.adds.count, 1)
    XCTAssertTrue(fake.deletes.isEmpty)
  }

  // Before first unlock (and any other status) proves nothing: no new key, no delete.
  func testUnavailableNeverCreatesOrDeletes() {
    for status in [errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed, -1] {
      let fake = FakeKeychain()
      fake.copyStatus = OSStatus(status)
      XCTAssertThrowsError(try keychain(fake).loadOrCreate())
      XCTAssertTrue(fake.adds.isEmpty, "created a key on status \(status)")
      XCTAssertTrue(fake.deletes.isEmpty)
      XCTAssertEqual(fake.reads, 4, "first read plus 3 retries")
    }
  }

  func testNotFoundIsRetriedBeforeANewKeyIsCreated() throws {
    let fake = FakeKeychain()
    _ = try keychain(fake).loadOrCreate()
    XCTAssertEqual(fake.reads, 5, "4 notFound reads, the create, a read-back")
  }

  func testWrongLengthItemIsReplacedOnlyWhenEveryAttemptAgrees() throws {
    let fake = FakeKeychain()
    fake.item = [kSecValueData as String: Data(repeating: 1, count: 16)]
    let loaded = try keychain(fake).loadOrCreate()
    XCTAssertEqual(loaded.key.count, 32)
    XCTAssertEqual(fake.deletes.count, 1)
    XCTAssertEqual(fake.adds.count, 1)
  }

  func testDuplicateOnCreateReadsTheWinnersKey() throws {
    let fake = FakeKeychain()
    fake.addStatus = errSecDuplicateItem
    let winner = Data(repeating: 9, count: 32)
    fake.winnerOnDuplicate = winner
    XCTAssertEqual(try keychain(fake).loadOrCreate().key, winner)
  }

  func testAddFailureIsUnavailable() {
    let fake = FakeKeychain()
    fake.addStatus = errSecInteractionNotAllowed
    XCTAssertThrowsError(try keychain(fake).loadOrCreate())
  }

  func testItemQueryNamesOnlyThisItem() {
    let q = SpoolKeychain.itemQuery(accessGroup: group)
    XCTAssertEqual(q[kSecAttrService as String] as? String, "app.zaghlol.spool")
    XCTAssertEqual(q[kSecAttrAccount as String] as? String, "spool_key_v1")
    // Distinct from the K_db item.
    XCTAssertNotEqual(q[kSecAttrService as String] as? String, DbKeyKeychain.service)
    XCTAssertNil(SpoolKeychain.itemQuery(accessGroup: nil)[kSecAttrAccessGroup as String])
  }

  func testSharedKeychainGroupNeedsAnExpandedPrefix() {
    XCTAssertEqual(
      ZaghlolSharedGroups.resolveKeychainGroup(prefix: "TEAM123.", suffix: "app.zaghlol.shared"),
      "TEAM123.app.zaghlol.shared")
    XCTAssertEqual(
      ZaghlolSharedGroups.resolveKeychainGroup(prefix: "TEAM123", suffix: "x.shared"),
      "TEAM123.x.shared")
    XCTAssertNil(ZaghlolSharedGroups.resolveKeychainGroup(prefix: "$(AppIdentifierPrefix)", suffix: "x"))
    XCTAssertNil(ZaghlolSharedGroups.resolveKeychainGroup(prefix: "", suffix: "x"))
    XCTAssertNil(ZaghlolSharedGroups.resolveKeychainGroup(prefix: "T.", suffix: nil))
  }

  // Per flavor: the App Group follows the bundle identifier (dev, staging, prod).
  func testAppGroupIsReadFromTheBundleAndFollowsTheBundleIdentifier() throws {
    let bundleId = try XCTUnwrap(Bundle.main.bundleIdentifier)
    XCTAssertEqual(ZaghlolSharedGroups.appGroup(), "group.\(bundleId)")
    XCTAssertEqual(ZaghlolDirectories.appGroupIdentifier, "group.\(bundleId)")
  }
}
