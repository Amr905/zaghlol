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
}
