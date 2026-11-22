import BackgroundTasks
import XCTest

@testable import Runner

/// FU-168e: the native backup wake-up keeps time and nothing else.
final class BackupWorkHostTests: XCTestCase {
  private func mark() -> BackupDueMark {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return BackupDueMark(url: dir.appendingPathComponent("backupwork/due"))
  }

  func testDueIsReadOnceThenCleared() {
    let m = mark()
    XCTAssertFalse(m.take())
    m.set()
    m.set()
    XCTAssertTrue(m.take())
    XCTAssertFalse(m.take())
  }

  func testScheduleSubmitsOneProcessingRequestThatNeedsNetwork() throws {
    var submitted: [BGTaskRequest] = []
    var cancelled: [String] = []
    let host = BackupWorkHost(
      mark: mark(), submit: { submitted.append($0) }, cancelRequest: { cancelled.append($0) })
    try host.schedule(periodDays: 7)
    XCTAssertEqual(cancelled, ["app.zaghlol.backup"])  // replaces an earlier request
    let request = try XCTUnwrap(submitted.first as? BGProcessingTaskRequest)
    XCTAssertEqual(submitted.count, 1)
    XCTAssertEqual(request.identifier, "app.zaghlol.backup")
    XCTAssertTrue(request.requiresNetworkConnectivity)
    XCTAssertFalse(request.requiresExternalPower)
    let wait = try XCTUnwrap(request.earliestBeginDate).timeIntervalSinceNow
    XCTAssertEqual(wait, 7 * 86_400, accuracy: 60)
  }

  func testOtherPeriodsAreRefusedAndNothingIsSubmitted() {
    var submitted = 0
    let host = BackupWorkHost(mark: mark(), submit: { _ in submitted += 1 }, cancelRequest: { _ in })
    XCTAssertThrowsError(try host.schedule(periodDays: 2))
    XCTAssertEqual(submitted, 0)
  }

  func testCancelClearsAPendingMark() throws {
    let m = mark()
    m.set()
    let host = BackupWorkHost(mark: m, submit: { _ in }, cancelRequest: { _ in })
    try host.cancel()
    XCTAssertFalse(m.take())
  }
}
