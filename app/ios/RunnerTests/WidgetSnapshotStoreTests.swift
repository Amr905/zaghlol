import XCTest

@testable import Runner

/// T-118: the encrypted widget snapshot store and the channel host. Synthetic
/// strings only.
final class WidgetSnapshotStoreTests: XCTestCase {
  private var dir: URL!
  private var file: URL!

  override func setUpWithError() throws {
    dir = try makeTempDir()
    file = dir.appendingPathComponent("widget/snapshot.bin")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  /// The production hook creates the directory (and excludes it from backup).
  private static let makeDir: (URL) throws -> Void = {
    try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
  }

  private func store(
    _ cipher: SpoolCipher = TestCipher(),
    exclude: @escaping (URL) throws -> Void = WidgetSnapshotStoreTests.makeDir
  ) -> WidgetSnapshotStore {
    WidgetSnapshotStore(file: file, cipher: cipher, excludeDir: exclude)
  }

  private func view(_ primary: String = "314.28 EGP/day") -> WidgetView {
    WidgetView(
      state: WidgetView.stateOk, primaryText: primary, secondaryText: "7 days to payday",
      currency: "EGP", updatedAtMs: 1_700_000_000_000, daysToPayday: 7)
  }

  func testRoundTripAndNotPlaintextOnDisk() throws {
    let s = store()
    try s.write(view())
    XCTAssertEqual(s.readOrNil(), view())
    let raw = try Data(contentsOf: file)
    XCTAssertNil(raw.range(of: Data("314".utf8)))
    XCTAssertNil(raw.range(of: Data("EGP".utf8)))
  }

  func testHiddenAmountSnapshotHoldsOnlyTheMask() throws {
    let s = store()
    try s.write(view("•••/day"))
    let read = try XCTUnwrap(s.readOrNil())
    XCTAssertEqual(read.primaryText, "•••/day")
    XCTAssertNil(read.primaryText.rangeOfCharacter(from: .decimalDigits))
  }

  func testTamperedOrWrongKeyOrWrongAadReadsAsNilAndKeepsTheFile() throws {
    let s = store()
    XCTAssertNil(s.readOrNil())
    try s.write(view())
    var bytes = try Data(contentsOf: file)
    bytes[bytes.count - 1] ^= 1
    try bytes.write(to: file)
    XCTAssertNil(s.readOrNil())
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

    try s.write(view())
    XCTAssertNil(store(TestCipher(seed: 9)).readOrNil())

    let cipher = TestCipher()
    let wrongAad = try cipher.encrypt(
      WidgetSnapshotStore.encode(view()), aad: Data("zaghlol.capture.v1|status".utf8))
    try wrongAad.write(to: file)
    XCTAssertNil(store(cipher).readOrNil())
  }

  func testRecordRejectsBadVersionStateAndTrailingBytes() throws {
    var good = WidgetSnapshotStore.encode(view())
    XCTAssertNoThrow(try WidgetSnapshotStore.decode(good))
    good.append(0)
    XCTAssertThrowsError(try WidgetSnapshotStore.decode(good))
    var badVersion = WidgetSnapshotStore.encode(view())
    badVersion[0] = 2
    XCTAssertThrowsError(try WidgetSnapshotStore.decode(badVersion))
    var badState = WidgetSnapshotStore.encode(view())
    badState[1] = 9
    XCTAssertThrowsError(try WidgetSnapshotStore.decode(badState))
  }

  func testWriteExcludesTheDirectoryFromBackupFirst() throws {
    var excluded: [URL] = []
    let s = store(exclude: { url in
      excluded.append(url)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    })
    try s.write(view())
    XCTAssertEqual(excluded.map { $0.lastPathComponent }, ["widget"])
  }

  func testClearIsIdempotent() throws {
    let s = store()
    XCTAssertNoThrow(try s.clear())
    try s.write(view())
    try s.clear()
    try s.clear()
    XCTAssertNil(s.readOrNil())
  }

  func testOverlongTextIsTruncated() throws {
    let s = store()
    try s.write(view(String(repeating: "x", count: 10_000)))
    XCTAssertEqual(s.readOrNil()?.primaryText.count, WidgetView.maxTextChars)
  }

  func testHostStoresReloadsAndMapsErrorsToCodes() throws {
    var reloads = 0
    let host = WidgetBridgeHost(store: store(), reload: { reloads += 1 })
    try host.updateSnapshot(
      snapshot: WidgetSnapshot(
        state: .noBudget, primaryText: "Set a budget", secondaryText: "", currency: "EGP",
        updatedAtMs: 5, daysToPayday: nil))
    XCTAssertEqual(reloads, 1)
    XCTAssertEqual(store().readOrNil()?.state, WidgetView.stateNoBudget)
    try host.clear()
    XCTAssertEqual(reloads, 2)
    XCTAssertNil(store().readOrNil())

    let snap = WidgetSnapshot(
      state: .ok, primaryText: "secret-sentinel", secondaryText: "", currency: "EGP",
      updatedAtMs: 1, daysToPayday: 1)
    let noGroup = WidgetBridgeHost(store: nil, reload: {})
    XCTAssertThrowsError(try noGroup.updateSnapshot(snapshot: snap)) { e in
      let err = e as? WidgetBridgeApiError
      XCTAssertEqual(err?.code, "NOT_AVAILABLE")
      XCTAssertNil(err?.message)
      XCTAssertNil(err?.details)
    }
    let failing = WidgetBridgeHost(
      store: store(exclude: { _ in throw WidgetSnapshotFormatError() }), reload: {})
    XCTAssertThrowsError(try failing.updateSnapshot(snapshot: snap)) { e in
      XCTAssertEqual((e as? WidgetBridgeApiError)?.code, "IO_ERROR")
    }
  }
}
