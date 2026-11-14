import Flutter
import Foundation

/// T-062 (ADR-006 addendum, SPK-03): processes the spool in a headless
/// Flutter engine, as an optimisation and never as the guarantee. The caller
/// wrote the encrypted spool entry first; this only tries to drain it now.
/// Any failure (engine start, ready, drain or close timeout) leaves the entry
/// in the spool, where the foreground drain or the BGAppRefreshTask picks it
/// up (at-least-once).
///
/// Rules from the spike:
/// - Install channel handlers only after `engine.run()` (the messenger aborts
///   the process otherwise); Dart retries `ready` until native answers.
/// - A hard timeout bounds the whole run. On timeout native asks Dart to
///   `close` (stop after the current batch, close the database) and waits
///   for it, bounded, before destroying the engine, so a transaction is not
///   cut mid-way by us.
/// - One headless run at a time per process.
/// - Nothing logged; only counts and a code leave Dart.
enum HeadlessIngestionError: Error, Equatable {
  case busy
  case engineDidNotStart
  case readyTimeout
  case drainTimeout
  case drainFailed
}

/// Numbers and a code only.
struct HeadlessIngestionResult: Equatable {
  var outcome: IngestOutcome
  var drained: Int64
  var inserted: Int64
  var stuck: Int64
  var held: Int64
  var code: String?
  var elapsedMs: Int
}

@MainActor
final class HeadlessIngestion {
  /// Suggested budget inside `perform()` until device numbers exist (ADR-006 addendum).
  static let intentTimeoutS: Double = 8
  /// A BGAppRefreshTask gets about 30 s; leave room for `close` and teardown.
  static let backgroundTimeoutS: Double = 20
  static let closeTimeoutS: Double = 3
  static let entrypoint = "ingestionMain"

  private static var running = false
  /// Set by the BGTask expiration handler: the loops stop waiting, ask Dart to
  /// `close` and tear down (never cancelled mid-transaction by a Task cancel).
  private static var stopRequested = false

  static func requestStop() { stopRequested = true }

  private final class ReadyHost: HeadlessIngestionHostApi {
    var isReady = false
    func ready() throws { isReady = true }
  }

  private static func nowMs() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

  /// Runs one drain cycle in a fresh headless engine within `timeoutS`.
  static func run(
    timeoutS: Double, entrypoint: String = HeadlessIngestion.entrypoint,
    register: (FlutterEngine) -> IosCaptureHost? = { IosCaptureRegistration.register(with: $0) }
  ) async throws -> HeadlessIngestionResult {
    guard !running else { throw HeadlessIngestionError.busy }
    running = true
    stopRequested = false
    defer { running = false }
    let t0 = nowMs()
    let deadline = t0 + Int(timeoutS * 1000)

    let engine = FlutterEngine(
      name: "zaghlol.ingest.headless", project: nil, allowHeadlessExecution: true)
    var host: IosCaptureHost?
    defer {
      host?.detach()
      engine.destroyContext()
    }
    guard engine.run(withEntrypoint: entrypoint) else { throw HeadlessIngestionError.engineDidNotStart }
    // Handlers only now: the shell exists after run().
    let readyHost = ReadyHost()
    HeadlessIngestionHostApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: readyHost)
    GeneratedPluginRegistrant.register(with: engine)
    SecretStoreRegistration.register(with: engine)
    host = register(engine)

    while !readyHost.isReady {
      if nowMs() > deadline || stopRequested { throw HeadlessIngestionError.readyTimeout }
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    let api = HeadlessIngestionApi(binaryMessenger: engine.binaryMessenger)
    var reply: Result<IngestCycleReport, IngestionApiError>?
    api.drain { reply = $0 }
    while reply == nil {
      if nowMs() > deadline || stopRequested {
        await close(api)
        throw HeadlessIngestionError.drainTimeout
      }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    // Always close: the database must be closed before the engine is destroyed.
    await close(api)
    guard case .success(let report)? = reply else { throw HeadlessIngestionError.drainFailed }
    return HeadlessIngestionResult(
      outcome: report.outcome, drained: report.drained, inserted: report.inserted,
      stuck: report.stuck, held: report.held, code: report.code, elapsedMs: nowMs() - t0)
  }

  /// Asks Dart to stop after the current batch and close the database, waiting
  /// at most `closeTimeoutS`.
  private static func close(_ api: HeadlessIngestionApi) async {
    var closed = false
    api.close { _ in closed = true }
    let limit = nowMs() + Int(closeTimeoutS * 1000)
    while !closed && nowMs() < limit {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }

  /// For App Intents: true only when the headless engine drained and everything
  /// it read was committed and acked (`ok`). Never throws; the spool entry
  /// stays on every other outcome.
  static func attempt(timeoutS: Double = HeadlessIngestion.intentTimeoutS) async -> Bool {
    do { return try await run(timeoutS: timeoutS).outcome == .ok } catch { return false }
  }
}
