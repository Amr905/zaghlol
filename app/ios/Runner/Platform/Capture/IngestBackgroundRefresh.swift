import BackgroundTasks
import Foundation

/// T-062: the best-effort nudge of the iOS fallback path (ADR-006 addendum):
/// a `BGAppRefreshTask` 'app.zaghlol.ingest' that drains the spool in a
/// headless engine. The system decides when (and whether) it runs; the
/// foreground drain is the guarantee.
///
/// The launch handler must be registered before the app finishes launching
/// (`registerLaunchHandler()` from `didFinishLaunching`); Dart then asks for a
/// schedule with `registerBackgroundRefresh`. The handler reschedules first,
/// so a failing run never ends the chain.
///
/// Info.plist: `BGTaskSchedulerPermittedIdentifiers` = [app.zaghlol.ingest]
/// and `UIBackgroundModes` = [fetch].
enum IngestBackgroundRefresh {
  static let identifier = "app.zaghlol.ingest"
  /// Earliest begin: the system may run it much later.
  static let minIntervalS: TimeInterval = 15 * 60

  struct SubmitFailure: Error {}

  static func registerLaunchHandler() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      handle(refresh)
    }
  }

  static func schedule(submit: (BGTaskRequest) throws -> Void = { try BGTaskScheduler.shared.submit($0) })
    throws
  {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: minIntervalS)
    do { try submit(request) } catch { throw SubmitFailure() }
  }

  private static func handle(_ task: BGAppRefreshTask) {
    try? schedule()
    Task { @MainActor in
      let ok = (try? await HeadlessIngestion.run(timeoutS: HeadlessIngestion.backgroundTimeoutS)) != nil
      task.setTaskCompleted(success: ok)
    }
    // Out of time: stop waiting; the run closes the database before teardown.
    task.expirationHandler = { Task { @MainActor in HeadlessIngestion.requestStop() } }
  }
}
