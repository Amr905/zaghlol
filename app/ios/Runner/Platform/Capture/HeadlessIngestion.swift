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
  /// FU-194: a restore holds the drain; no engine was started.
  case held
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
  /// FU-194: no engine starts while `hold` is in force (the restore swaps
  /// the database files); the run counts as active for the hold until it ends.
  static func run(
    timeoutS: Double, entrypoint: String = HeadlessIngestion.entrypoint,
    hold: DrainHold? = DrainHold.shared,
    register: (FlutterEngine) -> IosCaptureHost? = { IosCaptureRegistration.register(with: $0) }
  ) async throws -> HeadlessIngestionResult {
    guard !running else { throw HeadlessIngestionError.busy }
    if let hold = hold, !hold.admitEngine() { throw HeadlessIngestionError.held }
    running = true
    stopRequested = false
    defer {
      running = false
      hold?.engineGone()
    }
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

/// FU-194: the restore's drain hold (platform-channels.md 1.4). While it is in
/// force no headless run starts an engine, so nothing but the UI engine opens
/// the database while the restore swaps its files. Writers (App Intents, the
/// Share Extension) still write to the spool.
///
/// - Persisted in `<App Group>/Library/Application Support/capture/drain_hold`
///   (ASCII epoch ms of the expiry; no content; directory excluded from
///   backup), so it survives a process death mid-restore. Without an App
///   Group container it is held in memory only.
/// - Expires after at most `maxTtlMs` (wall clock); an expiry further ahead
///   than that (clock set back) counts as expired, so a crash never stops the
///   headless drain for longer.
/// - `admitEngine` and `hold` share one lock: either the hold sees the run
///   that was admitted (`hold` returns true) or the run sees the hold.
final class DrainHold {
  static let maxTtlMs: Int64 = 10 * 60_000
  static let fileName = "drain_hold"

  static let shared = DrainHold(
    file: SpoolLocation.containerURL().map {
      SpoolLocation.statusFile(in: $0).deletingLastPathComponent().appendingPathComponent(fileName)
    })

  struct WriteFailure: Error {}

  private let file: URL?
  private let wallMs: () -> Int64
  private let lock = NSLock()
  private var untilMs: Int64
  private var engineActive = false

  init(
    file: URL?,
    wallMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.file = file
    self.wallMs = wallMs
    self.untilMs = DrainHold.load(file)
  }

  /// True while a hold is in force.
  func isHeld() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return heldLocked()
  }

  /// True while a headless run is in progress.
  func headlessActive() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return engineActive
  }

  /// Sets (or renews) the hold for `ttlMs`, capped to 1...maxTtlMs. The file
  /// is written first; when that fails this throws and no hold is set.
  /// Returns whether a headless run is active now.
  @discardableResult
  func hold(ttlMs: Int64) throws -> Bool {
    let until = wallMs() + Swift.min(Swift.max(ttlMs, 1), Self.maxTtlMs)
    try persist(until)
    lock.lock()
    defer { lock.unlock() }
    untilMs = until
    return engineActive
  }

  /// Clears the hold (idempotent). The memory hold is cleared even when the
  /// delete fails (it then throws).
  func release() throws {
    lock.lock()
    untilMs = 0
    lock.unlock()
    guard let file = file, FileManager.default.fileExists(atPath: file.path) else { return }
    do { try FileManager.default.removeItem(at: file) } catch {
      if FileManager.default.fileExists(atPath: file.path) { throw WriteFailure() }
    }
  }

  /// Right before a headless run starts its engine: false while held, else
  /// marks the run active until `engineGone()`.
  func admitEngine() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if heldLocked() { return false }
    engineActive = true
    return true
  }

  func engineGone() {
    lock.lock()
    engineActive = false
    lock.unlock()
  }

  private func heldLocked() -> Bool {
    guard untilMs > 0 else { return false }
    let now = wallMs()
    return now < untilMs && untilMs - now <= Self.maxTtlMs
  }

  private static func load(_ file: URL?) -> Int64 {
    guard let file = file, let data = try? Data(contentsOf: file),
      let text = String(data: data, encoding: .ascii),
      let v = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return 0 }
    return v
  }

  private func persist(_ until: Int64) throws {
    guard let file = file else { return }
    do {
      try ZaghlolDirectories.ensureExcluded(file.deletingLastPathComponent())
      try Data(String(until).utf8).write(
        to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch {
      throw WriteFailure()
    }
  }
}
