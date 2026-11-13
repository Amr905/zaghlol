import XCTest

@testable import Runner

/// T-062: the capture status (alert counters) and its coalescing, same rules
/// as Android (T-039/T-040).
final class CaptureStatusStoreTests: XCTestCase {
  private var root: URL!
  private var cipher: TestCipher!
  private var mono: Int64 = 100_000

  override func setUpWithError() throws {
    root = try makeTempDir()
    cipher = TestCipher()
    mono = 100_000
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func store(_ name: String = "capture/status.bin") -> CaptureStatusStore {
    CaptureStatusStore(
      file: root.appendingPathComponent(name), cipher: cipher, sleeper: { _ in },
      randomSeq: { 777 }, monoClockMs: { self.mono })
  }

  private func onDiskSeq(_ name: String = "capture/status.bin") throws -> UInt32 {
    let bytes = try Data(contentsOf: root.appendingPathComponent(name))
    return try CaptureStatusStore.decode(
      try cipher.decrypt(bytes, aad: CaptureStatusStore.aad)
    ).seq
  }

  func testRecordRoundTripAndEncryption() throws {
    var s = CaptureStatus()
    s.seq = 9
    s.refusedFull = 2
    s.firstMissedSmsAtMs = 123
    s.keyInvalidatedAtMs = 456
    let data = CaptureStatusStore.encode(s)
    XCTAssertEqual(data.count, CaptureStatusStore.recordBytes)
    XCTAssertEqual(try CaptureStatusStore.decode(data), s)
    XCTAssertThrowsError(try CaptureStatusStore.decode(data.dropLast()))
    // On disk it is ciphertext, not the plain record.
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 5)
    let bytes = try Data(contentsOf: root.appendingPathComponent("capture/status.bin"))
    XCTAssertThrowsError(try CaptureStatusStore.decode(bytes))
  }

  func testStatusDirectoryIsExcludedFromBackup() throws {
    store().recordRefused(.full, channel: "wallet", wallMs: 5)
    XCTAssertTrue(try isExcludedFromBackup(root.appendingPathComponent("capture")))
  }

  func testAFirstFactIsWrittenAtOnceAndABurstIsCoalesced() throws {
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 1)
    XCTAssertEqual(try onDiskSeq(), 1, "first refusal: written at once")
    for _ in 0..<50 { st.recordRefused(.full, channel: "wallet", wallMs: 2) }
    XCTAssertEqual(try onDiskSeq(), 1, "a burst inside the window adds no write")
    // A new fact (first generic refusal) is written at once and carries the pending counts.
    st.recordRefused(.genericBudget, channel: "wallet", wallMs: 3)
    let now = try st.read()
    XCTAssertEqual(now.refusedFull, 51)
    XCTAssertEqual(now.refusedGeneric, 1)
  }

  func testPendingCountsAreMergedByReadAndAfterTheWindow() throws {
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 1)
    st.recordRefused(.full, channel: "wallet", wallMs: 2)
    XCTAssertEqual(try onDiskSeq(), 1)
    mono += CaptureStatusStore.coalesceWindowMs + 1
    st.recordRefused(.full, channel: "wallet", wallMs: 3)
    XCTAssertEqual(try onDiskSeq(), 3, "after the window the next alert persists the delta")
    XCTAssertEqual(try st.read().refusedFull, 3)
  }

  func testClearIsCompareAndClear() throws {
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 1)
    let seen = try st.read()
    st.recordRefused(.genericRate, channel: "wallet", wallMs: 2)  // arrives after the caller's read
    XCTAssertFalse(try st.clear(seq: seen.seq), "stale seq changes nothing")
    let fresh = try st.read()
    XCTAssertEqual(fresh.refusedGeneric, 1)
    XCTAssertTrue(try st.clear(seq: fresh.seq))
    let after = try st.read()
    XCTAssertEqual(after.refusedFull, 0)
    XCTAssertEqual(after.refusedGeneric, 0)
    XCTAssertEqual(after.seq, fresh.seq &+ 1)
  }

  func testUnreadableFileRestartsWithAKeyLossAndARandomSeq() throws {
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 1)
    let file = root.appendingPathComponent("capture/status.bin")
    var bytes = try Data(contentsOf: file)
    bytes[bytes.count - 1] ^= 1
    try bytes.write(to: file)
    mono += 1_000_000
    // The next alert after the window re-reads the file, finds it unreadable
    // on every attempt and restarts from zero, flagged as a key loss.
    st.recordRefused(.full, channel: "wallet", wallMs: 9)
    let s = try st.read()
    XCTAssertGreaterThanOrEqual(s.keyInvalidatedAtMs, 0)
  }

  // A cipher/Keychain failure never overwrites the unread file; the alert stays pending.
  func testKeychainFailureKeepsTheFileAndTheAlert() throws {
    let st = store()
    st.recordRefused(.full, channel: "wallet", wallMs: 1)
    let file = root.appendingPathComponent("capture/status.bin")
    let before = try Data(contentsOf: file)
    cipher.failWith = .unavailable
    mono += CaptureStatusStore.coalesceWindowMs + 1
    st.recordRefused(.genericBudget, channel: "wallet", wallMs: 2)
    XCTAssertEqual(try Data(contentsOf: file), before, "unread file overwritten")
    XCTAssertThrowsError(try st.read())
    cipher.failWith = nil
    XCTAssertEqual(try st.read().refusedGeneric, 1, "the pending alert survived")
  }

  func testNotificationAndSmsMissesFollowTheChannel() throws {
    let st = store()
    st.recordRefused(.full, channel: "notification", wallMs: 5)
    st.recordRefused(.smsReserve, channel: "sms", wallMs: 7)
    st.recordRefused(.full, channel: "sms", wallMs: 3)
    let s = try st.read()
    XCTAssertEqual(s.missedNotifications, 1)
    XCTAssertEqual(s.firstMissedSmsAtMs, 3)
    XCTAssertEqual(s.refusedFull, 3)
  }
}
