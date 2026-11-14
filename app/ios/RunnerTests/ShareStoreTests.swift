import XCTest

@testable import Runner

/// T-065: the encrypted share store. Synthetic content only.
final class ShareStoreTests: XCTestCase {
  private var dir: URL!
  private var clock: Int64 = 1_700_000_000_000

  override func setUpWithError() throws {
    dir = try makeTempDir().appendingPathComponent("files", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
  }

  private func makeStore(
    cipher: SpoolCipher = TestCipher(), ops: SpoolFileOps = DefaultSpoolFileOps()
  ) -> ShareStore {
    ShareStore(dir: dir, cipher: cipher, files: ops, wallClock: { self.clock })
  }

  private func listing() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
  }

  func testRoundTripAndNothingInPlaintextOnDisk() throws {
    let store = makeStore()
    var payload = Data("hello \(spoolCanary) EGP 12.50".utf8)
    let meta = try store.add(kind: .text, mimeType: "text/plain", payload: &payload)
    XCTAssertEqual(payload, Data(repeating: 0, count: payload.count), "payload zeroed")
    XCTAssertEqual(store.list(), [meta])
    for name in listing() {
      let bytes = try Data(contentsOf: dir.appendingPathComponent(name))
      XCTAssertNil(bytes.range(of: Data(spoolCanary.utf8)), "plaintext in \(name)")
      XCTAssertNil(bytes.range(of: Data("text/plain".utf8)), "plaintext metadata in \(name)")
    }
    XCTAssertEqual(listing().sorted(), ["\(meta.id).bin", "\(meta.id).meta"])
    let read = try store.read(meta.id)
    XCTAssertEqual(String(decoding: read.payload, as: UTF8.self), "hello \(spoolCanary) EGP 12.50")
    XCTAssertTrue(try isExcludedFromBackup(dir), "files dir excluded before the first write")
    store.discard(meta.id)
    store.discard(meta.id)  // idempotent
    XCTAssertEqual(listing(), [])
  }

  func testSwappedBodyIsNotAuthenticAndDeleted() throws {
    let store = makeStore()
    var a = Data("one".utf8)
    var b = Data("two".utf8)
    let ma = try store.add(kind: .text, mimeType: "text/plain", payload: &a)
    let mb = try store.add(kind: .text, mimeType: "text/plain", payload: &b)
    let fm = FileManager.default
    try fm.removeItem(at: dir.appendingPathComponent("\(ma.id).bin"))
    try fm.copyItem(
      at: dir.appendingPathComponent("\(mb.id).bin"), to: dir.appendingPathComponent("\(ma.id).bin"))
    XCTAssertThrowsError(try store.read(ma.id)) { XCTAssertEqual($0 as? ShareStoreError, .notAuthentic) }
    XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("\(ma.id).meta").path))
    XCTAssertNoThrow(try store.read(mb.id))
  }

  func testCipherFailureKeepsTheShare() throws {
    let cipher = TestCipher()
    let store = makeStore(cipher: cipher)
    var p = Data("x".utf8)
    let m = try store.add(kind: .text, mimeType: "text/plain", payload: &p)
    cipher.failWith = .unavailable
    XCTAssertThrowsError(try store.read(m.id)) { XCTAssertEqual($0 as? ShareStoreError, .unavailable) }
    XCTAssertEqual(store.list(), [])  // skipped, not deleted
    XCTAssertEqual(listing().count, 2)
    cipher.failWith = nil
    XCTAssertEqual(store.list(), [m])
  }

  func testStaleShareIsPurgedAndOrphanMetaIsRemoved() throws {
    let store = makeStore()
    var a = Data("old".utf8)
    var b = Data("gone".utf8)
    let old = try store.add(kind: .text, mimeType: "text/plain", payload: &a)
    let consumed = try store.add(kind: .image, mimeType: "image/png", payload: &b)
    try FileManager.default.removeItem(at: dir.appendingPathComponent("\(consumed.id).bin"))  // OCR consumed it
    XCTAssertEqual(store.list().map(\.id), [old.id])
    clock += ShareStore.staleAgeMs + 1
    XCTAssertEqual(store.list(), [])
    XCTAssertEqual(listing(), [])
  }

  func testLimitsRefuseTheEleventhShare() throws {
    let store = makeStore()
    for _ in 0..<ShareStore.maxPending {
      var p = Data("x".utf8)
      _ = try store.add(kind: .text, mimeType: "text/plain", payload: &p)
    }
    var p = Data("x".utf8)
    XCTAssertThrowsError(try store.add(kind: .text, mimeType: "text/plain", payload: &p)) {
      XCTAssertEqual($0 as? ShareStoreError, .tooLarge)
    }
  }

  func testRejectionSlotIsOnce() {
    let store = makeStore()
    store.setRejection(.unsupportedType)
    XCTAssertEqual(store.takeRejection(), .unsupportedType)
    XCTAssertNil(store.takeRejection())
  }

  func testIdValidationBlocksPathTraversal() {
    XCTAssertFalse(ShareStore.isValidId("../../etc/passwd"))
    XCTAssertFalse(ShareStore.isValidId(""))
    XCTAssertTrue(ShareStore.isValidId(SpoolUlidGenerator().next()))
    XCTAssertThrowsError(try makeStore().read("../x"))
  }
}
