import BackgroundTasks
import XCTest

@testable import Runner

/// T-062: the Pigeon host over the spool: drain/ack/hold scoping, the drain
/// claim, the status calls and code-only errors. Synthetic bodies only.
final class IosCaptureHostTests: XCTestCase {
  private var root: URL!
  private var runtime: SpoolRuntime!
  private var claim: SpoolClaim!

  override func setUpWithError() throws {
    root = try makeTempDir()
    let cipher = TestCipher()
    let status = CaptureStatusStore(
      file: root.appendingPathComponent("capture/status.bin"), cipher: cipher, sleeper: { _ in })
    let store = SpoolStore(
      dir: root.appendingPathComponent("spool"), cipher: cipher, status: status, sleeper: { _ in })
    runtime = SpoolRuntime(store: store, status: status, cipher: KeychainSpoolCipher())
    claim = SpoolClaim()
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func host(refresh: @escaping () throws -> Void = {}) -> IosCaptureHost {
    IosCaptureHost(
      runtime: { self.runtime }, claim: claim, scheduleRefresh: refresh, guardRuntime: { nil })
  }

  @discardableResult
  private func put(_ n: Int, channel: String = "shortcut_message") throws -> String {
    guard
      case .written(let id) = try runtime.store.write(
        sampleRecord("msg \(n) \(spoolCanary)", channel: channel), cls: .priority)
    else { throw XCTSkip("refused") }
    return id
  }

  func testDrainReturnsDecryptedEntriesOldestFirst() throws {
    let a = try put(1)
    let b = try put(2, channel: "wallet")
    let entries = try host().drainSpool(max: 10)
    XCTAssertEqual(entries.map { $0.id }, [a, b].sorted())
    XCTAssertEqual(entries.first?.body, "msg 1 \(spoolCanary)")
    XCTAssertEqual(entries.last?.channel, "wallet")
    XCTAssertEqual(entries.first?.source, "SYNTH-BANK")
  }

  func testDrainRespectsMaxAndTheCap() throws {
    for i in 0..<5 { try put(i) }
    let h = host()
    XCTAssertEqual(try h.drainSpool(max: 2).count, 2)
    XCTAssertEqual(try h.drainSpool(max: 0).count, 1, "max is at least 1")
    XCTAssertEqual(try h.drainSpool(max: 100_000).count, 5)
  }

  // Ack deletes only what this engine drained.
  func testAckIsScopedToWhatThisEngineDrained() throws {
    let a = try put(1)
    let b = try put(2)
    let h = host()
    _ = try h.drainSpool(max: 1)  // drains a only
    try h.ackSpool(ids: [a, b])
    XCTAssertEqual(runtime.store.pendingIds(), [b], "b was never drained by this engine")
    try h.ackSpool(ids: [a])  // idempotent
  }

  func testAckWithTooManyIdsIsACodeOnlyIoError() throws {
    let ids = (0..<101).map { _ in SpoolUlidGenerator().next() }
    XCTAssertThrowsError(try host().ackSpool(ids: ids)) { e in
      let err = e as? CaptureApiError
      XCTAssertEqual(err?.code, "IO_ERROR")
      XCTAssertNil(err?.message)
      XCTAssertNil(err?.details)
    }
  }

  // One engine at a time: the UI engine and a headless one never process the same entry.
  func testSecondEngineGetsNothingWhileTheFirstHoldsTheClaim() throws {
    let a = try put(1)
    let ui = host()
    let headless = host()
    XCTAssertEqual(try ui.drainSpool(max: 10).map { $0.id }, [a])
    XCTAssertEqual(try headless.drainSpool(max: 10).count, 0)
    try ui.ackSpool(ids: [a])
    let b = try put(2)
    XCTAssertEqual(try headless.drainSpool(max: 10).map { $0.id }, [b], "claim released by the ack")
  }

  func testDetachReleasesTheClaimAndKeepsTheEntries() throws {
    let a = try put(1)
    let ui = host()
    _ = try ui.drainSpool(max: 10)
    ui.detach()
    XCTAssertEqual(try host().drainSpool(max: 10).map { $0.id }, [a])
  }

  func testHoldMovesTheEntryAndReleasesItFromTheClaim() throws {
    let a = try put(1)
    let h = host()
    _ = try h.drainSpool(max: 10)
    try h.holdSpool(ids: [a])
    XCTAssertEqual(runtime.store.pendingIds(), [])
    XCTAssertEqual(runtime.store.heldCount(), 1)
    XCTAssertEqual(try h.getSpoolStatus().held, 1)
    XCTAssertEqual(h.ackableCount, 0)
  }

  func testStatusAndClear() throws {
    var limits = SpoolLimits()
    limits.maxEntries = 1
    let store = SpoolStore(
      dir: root.appendingPathComponent("spool2"), cipher: TestCipher(), status: runtime.status,
      sleeper: { _ in }, limits: limits)
    _ = try store.write(sampleRecord(), cls: .priority)
    XCTAssertEqual(try store.write(sampleRecord(), cls: .priority), .refused(.full))
    let h = host()
    let s = try h.getSpoolStatus()
    XCTAssertEqual(s.refusedFull, 1)
    XCTAssertNil(s.firstMissedSmsAtMs, "no sms channel on iOS")
    XCTAssertEqual(s.guardState, .unknown)
    try h.clearSpoolAlerts(seq: s.seq)
    XCTAssertEqual(try h.getSpoolStatus().refusedFull, 0)
    try h.clearSpoolAlerts(seq: -5)  // can't match a real seq: ignored
    try h.clearSpoolAlerts(seq: Int64(UInt32.max) + 10)
  }

  func testWithoutAContainerEveryCallIsNotAvailable() {
    let h = IosCaptureHost(runtime: { nil }, claim: SpoolClaim())
    XCTAssertThrowsError(try h.drainSpool(max: 1)) {
      XCTAssertEqual(($0 as? CaptureApiError)?.code, "NOT_AVAILABLE")
    }
    XCTAssertThrowsError(try h.getSpoolStatus())
    XCTAssertThrowsError(try h.ackSpool(ids: []))
  }

  func testRegisterBackgroundRefreshSchedulesAndFailureIsCodeOnly() throws {
    var scheduled = 0
    try host(refresh: { scheduled += 1 }).registerBackgroundRefresh()
    XCTAssertEqual(scheduled, 1)
    struct Boom: Error {}
    XCTAssertThrowsError(try host(refresh: { throw Boom() }).registerBackgroundRefresh()) {
      XCTAssertEqual(($0 as? CaptureApiError)?.code, "IO_ERROR")
      XCTAssertNil(($0 as? CaptureApiError)?.message)
    }
  }

  func testBackgroundRefreshRequestIsTheDocumentedIdentifierAndNotImmediate() throws {
    var seen: BGTaskRequestProbe?
    try IngestBackgroundRefresh.schedule { request in
      seen = BGTaskRequestProbe(identifier: request.identifier, earliest: request.earliestBeginDate)
    }
    XCTAssertEqual(seen?.identifier, "app.zaghlol.ingest")
    XCTAssertGreaterThan(seen?.earliest?.timeIntervalSinceNow ?? 0, 10 * 60)
    XCTAssertThrowsError(try IngestBackgroundRefresh.schedule { _ in throw NSError(domain: "x", code: 1) }) {
      XCTAssertTrue($0 is IngestBackgroundRefresh.SubmitFailure, "no system error text escapes")
    }
  }

  // The declared identifiers match what the code submits (a mismatch makes submit fail at runtime).
  func testInfoPlistPermitsTheBackgroundTaskAndFetchMode() {
    let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
    XCTAssertEqual(ids, [IngestBackgroundRefresh.identifier])
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    XCTAssertEqual(modes?.contains("fetch"), true)
  }
}

struct BGTaskRequestProbe {
  let identifier: String
  let earliest: Date?
}
