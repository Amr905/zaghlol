import Flutter
import XCTest

@testable import Runner

/// T-062 (ADR-006 addendum): the headless run is an optimisation, never the
/// guarantee. Whatever happens to the engine, the encrypted spool entry is
/// still there for the foreground drain / BGAppRefreshTask. Synthetic text only.
@MainActor
final class HeadlessIngestionTests: XCTestCase {
  private var root: URL!
  private var runtime: SpoolRuntime!

  override func setUpWithError() throws {
    root = try makeTempDir()
    let cipher = TestCipher()
    let status = CaptureStatusStore(
      file: root.appendingPathComponent("capture/status.bin"), cipher: cipher, sleeper: { _ in })
    let store = SpoolStore(
      dir: root.appendingPathComponent("spool"), cipher: cipher, status: status, sleeper: { _ in })
    runtime = SpoolRuntime(store: store, status: status, cipher: KeychainSpoolCipher())
  }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func register(_ engine: FlutterEngine) -> IosCaptureHost? {
    IosCaptureRegistration.register(
      with: engine, host: IosCaptureHost(runtime: { self.runtime }, claim: SpoolClaim()))
  }

  private func writeEntry() throws -> String {
    guard case .written(let id) = try runtime.store.write(sampleRecord(), cls: .priority) else {
      throw XCTSkip("refused")
    }
    return id
  }

  // An engine that does not answer in time throws; the entry stays in the spool.
  func testTimeoutLeavesTheEntryInTheSpool() async throws {
    let id = try writeEntry()
    do {
      _ = try await HeadlessIngestion.run(timeoutS: 0.001, register: register)
      XCTFail("expected a timeout")
    } catch let e as HeadlessIngestionError {
      XCTAssertEqual(e, .readyTimeout)
    }
    XCTAssertEqual(runtime.store.pendingIds(), [id])
    let ok = await HeadlessIngestion.attempt(timeoutS: 0.001)
    XCTAssertFalse(ok)
    XCTAssertEqual(runtime.store.pendingIds(), [id])
  }

  // With the real entrypoint: the entry is removed only when the cycle reports ok
  // (acked after the DB commit); a missing or locked database leaves it for the UI engine.
  func testEntryIsAckedOnlyWhenTheCycleIsOk() async throws {
    let id = try writeEntry()
    let result = try await HeadlessIngestion.run(timeoutS: 30, register: register)
    if result.outcome == .ok {
      XCTAssertEqual(runtime.store.pendingIds().contains(id), result.drained == 0)
    } else {
      XCTAssertEqual(runtime.store.pendingIds(), [id])
    }
  }

  // FU-194 negative proof: while a restore holds the drain, a headless run
  // (App Intent, BGAppRefreshTask) starts no engine; the entry stays.
  func testAHeldDrainStartsNoEngineAndTheEntryStays() async throws {
    let id = try writeEntry()
    var now: Int64 = 1_800_000_000_000
    let hold = DrainHold(file: root.appendingPathComponent("capture/drain_hold"), wallMs: { now })
    try hold.hold(ttlMs: 60_000)
    var registered = 0
    do {
      _ = try await HeadlessIngestion.run(timeoutS: 30, hold: hold) { engine in
        registered += 1
        return self.register(engine)
      }
      XCTFail("expected held")
    } catch let e as HeadlessIngestionError {
      XCTAssertEqual(e, .held)
    }
    XCTAssertEqual(registered, 0, "no engine was started")
    XCTAssertFalse(hold.headlessActive())
    XCTAssertEqual(runtime.store.pendingIds(), [id])
    // Expired: the run is admitted again (it then times out at once here).
    now += 60_000
    do { _ = try await HeadlessIngestion.run(timeoutS: 0.001, hold: hold, register: register) } catch let e
      as HeadlessIngestionError
    {
      XCTAssertNotEqual(e, .held)
    }
    XCTAssertFalse(hold.headlessActive(), "the run counts as active only while it runs")
  }
}

/// FU-194: the drain hold itself (persisted, bounded, ordered with the run).
final class DrainHoldTests: XCTestCase {
  private var root: URL!
  private var now: Int64 = 1_800_000_000_000

  override func setUpWithError() throws { root = try makeTempDir() }
  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private var file: URL { root.appendingPathComponent("capture/drain_hold") }
  private func hold() -> DrainHold { DrainHold(file: file, wallMs: { self.now }) }

  func testAHoldSurvivesANewProcessAndReleaseClearsIt() throws {
    try hold().hold(ttlMs: 60_000)
    let again = hold()
    XCTAssertTrue(again.isHeld())
    XCTAssertFalse(again.admitEngine())
    try again.release()
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertFalse(hold().isHeld())
  }

  // Negative proof: an expired hold (a crashed restore) no longer blocks.
  func testAnExpiredHoldNoLongerBlocks() throws {
    let h = hold()
    try h.hold(ttlMs: 60_000)
    now += 60_000
    XCTAssertFalse(h.isHeld())
    XCTAssertTrue(h.admitEngine())
    XCTAssertFalse(hold().isHeld())
  }

  func testTheTtlIsCappedAndAClockSetBackCountsAsExpired() throws {
    let h = hold()
    try h.hold(ttlMs: Int64.max / 2)
    now += DrainHold.maxTtlMs
    XCTAssertFalse(h.isHeld())
    try h.hold(ttlMs: 60_000)
    now -= DrainHold.maxTtlMs + 1
    XCTAssertFalse(h.isHeld())
  }

  func testHoldReportsTheAdmittedRunUntilItIsGone() throws {
    let h = hold()
    XCTAssertTrue(h.admitEngine())
    XCTAssertTrue(try h.hold(ttlMs: 60_000))
    h.engineGone()
    XCTAssertFalse(h.headlessActive())
    XCTAssertFalse(h.admitEngine())
  }

  func testTheHoldDirectoryIsExcludedFromBackup() throws {
    try hold().hold(ttlMs: 60_000)
    let dir = URL(fileURLWithPath: file.deletingLastPathComponent().path, isDirectory: true)
    XCTAssertEqual(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }

  func testTheHostAsksARunningDrainToStopAndAnswersCodeOnly() throws {
    let h = hold()
    var stops = 0
    let host = IosCaptureHost(runtime: { nil }, claim: SpoolClaim(), drainHold: h, stopHeadless: { stops += 1 })
    XCTAssertFalse(try host.holdDrain(ttlMs: 60_000))
    XCTAssertEqual(stops, 0)
    XCTAssertTrue(h.admitEngine() == false)
    try host.releaseDrainHold()
    XCTAssertTrue(h.admitEngine())
    XCTAssertTrue(try host.holdDrain(ttlMs: 60_000), "works without the spool runtime")
    XCTAssertEqual(stops, 1)
    XCTAssertTrue(try host.isHeadlessDrainActive())
  }
}
