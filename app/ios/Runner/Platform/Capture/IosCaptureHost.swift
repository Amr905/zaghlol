import Flutter
import Foundation

/// T-062: the Pigeon `IosCaptureHostApi` over the encrypted App Group spool
/// (platform-channels.md 1.3 and section 3). One host per engine (the UI
/// engine and each headless engine), so acks are scoped to what that engine
/// drained. Every failure is a code-only error (`IO_ERROR`, `NOT_AVAILABLE`);
/// nothing is logged and no message text is ever put in an error.
final class IosCaptureHost: IosCaptureHostApi {
  static let maxDrain = 100
  /// A drain stops scanning after this long (monotonic ms).
  static let drainScanBudgetMs: Int64 = 5_000
  static let notAvailable = "NOT_AVAILABLE"
  static let ioError = "IO_ERROR"
  static let configInvalid = "CONFIG_INVALID"

  private static let nextEngine = NSLock()
  private static var engineCounter: Int64 = 0
  private static func newEngineId() -> Int64 {
    nextEngine.lock()
    defer { nextEngine.unlock() }
    engineCounter += 1
    return engineCounter
  }

  let engineId: Int64
  private let runtime: () -> SpoolRuntime?
  private let claim: SpoolClaim
  private let monoClockMs: () -> Int64
  private let scheduleRefresh: () throws -> Void
  private let guardRuntime: () -> GuardRuntime?
  private let drainedLock = NSLock()
  private var drained = Set<String>()

  init(
    runtime: @escaping () -> SpoolRuntime? = { SpoolRuntime.shared },
    claim: SpoolClaim = .process,
    monoClockMs: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
    scheduleRefresh: @escaping () throws -> Void = { try IngestBackgroundRefresh.schedule() },
    guardRuntime: @escaping () -> GuardRuntime? = { CaptureGuardRuntime.shared }
  ) {
    self.engineId = IosCaptureHost.newEngineId()
    self.runtime = runtime
    self.claim = claim
    self.monoClockMs = monoClockMs
    self.scheduleRefresh = scheduleRefresh
    self.guardRuntime = guardRuntime
  }

  private func need() throws -> SpoolRuntime {
    guard let r = runtime() else { throw CaptureApiError(code: Self.notAvailable, message: nil, details: nil) }
    return r
  }

  private func fail(_ code: String = IosCaptureHost.ioError) -> CaptureApiError {
    CaptureApiError(code: code, message: nil, details: nil)
  }

  /// T-063: replaces the Guard user part the App Intents use (same runtime
  /// instance, so the next intent in this process sees it; later processes
  /// read the file). Code-only errors; the bytes are never logged or kept.
  func writeGuardConfig(userConfigJson: FlutterStandardTypedData) throws {
    guard let g = guardRuntime() else { throw fail(Self.notAvailable) }
    do {
      try g.writeUser(userConfigJson.data)
    } catch let e as GuardConfigWriteError {
      throw fail(e.code == .configInvalid ? Self.configInvalid : Self.ioError)
    } catch {
      throw fail()
    }
  }

  func drainSpool(max: Int64) throws -> [SpoolEntry] {
    let r = try need()
    r.store.sweepTmp()
    guard claim.acquire(engineId) else { return [] }
    let limit = Int(Swift.min(Swift.max(max, 1), Int64(Self.maxDrain)))
    var out: [SpoolEntry] = []
    let scope = SpoolDrainScope()
    let pending = r.store.pendingIds()
    // Ids that left the spool (acked by another engine after a claim expiry,
    // deleted on proof, or held) can't be acked here any more: forget them.
    drainedLock.lock()
    drained.formIntersection(pending)
    drainedLock.unlock()
    let started = monoClockMs()
    scan: for id in pending {
      if out.count >= limit || monoClockMs() - started >= Self.drainScanBudgetMs { break }
      switch r.store.read(id, scope: scope) {
      case .ok(let rec):
        out.append(
          SpoolEntry(
            id: id, channel: rec.channel, source: rec.source, body: rec.body,
            receivedAtMs: rec.receivedAtMs, simSlot: rec.simSlot.map { Int64($0) }))
      case .unavailable(let keyRelated):
        if keyRelated { break scan }
      case .deleted, .missing:
        break
      }
    }
    r.status.recordDrain(scope)
    let ids = out.map { $0.id }
    drainedLock.lock()
    drained.formUnion(ids)
    drainedLock.unlock()
    claim.hold(engineId, ids)
    return out
  }

  private func ownIds(_ ids: [String]) throws -> [String] {
    if ids.count > Self.maxDrain { throw fail() }
    drainedLock.lock()
    defer { drainedLock.unlock() }
    return ids.filter { SpoolUlidGenerator.isValid($0) && drained.contains($0) }
  }

  /// Idempotent. Dart calls it after the DB commit (or after its drain-time
  /// Guard re-check dropped the entry); only ids this engine drained.
  func ackSpool(ids: [String]) throws {
    let r = try need()
    let own = try ownIds(ids)
    r.store.ack(own)
    drainedLock.lock()
    drained.subtract(own)
    drainedLock.unlock()
    claim.acked(engineId, own)
  }

  /// Entries this host drained that the use case could not store even alone:
  /// moved to `spool/held/` and released from the claim like an ack.
  func holdSpool(ids: [String]) throws {
    let r = try need()
    let own = try ownIds(ids)
    var held: [String] = []
    defer {
      drainedLock.lock()
      drained.subtract(held)
      drainedLock.unlock()
      claim.acked(engineId, held)
    }
    do {
      for id in own {
        if try r.store.hold(id) { held.append(id) }
      }
    } catch {
      throw fail()
    }
  }

  func getSpoolStatus() throws -> SpoolStatus {
    let r = try need()
    let s: CaptureStatus
    do { s = try r.status.read() } catch { throw fail() }
    return SpoolStatus(
      pending: Int64(r.store.pendingCount()), seq: Int64(s.seq),
      refusedFull: Int64(s.refusedFull), refusedGeneric: Int64(s.refusedGeneric),
      rateLimited: Int64(s.rateLimited), missedNotifications: Int64(s.missedNotifications),
      firstMissedSmsAtMs: s.firstMissedSmsAtMs >= 0 ? s.firstMissedSmsAtMs : nil,
      decryptDeleted: Int64(s.decryptDeleted),
      keyInvalidatedAtMs: s.keyInvalidatedAtMs >= 0 ? s.keyInvalidatedAtMs : nil,
      guardState: CaptureGuardRuntime.state(of: guardRuntime()), held: Int64(r.store.heldCount()))
  }

  func clearSpoolAlerts(seq: Int64) throws {
    let r = try need()
    guard seq >= 0, seq <= Int64(UInt32.max) else { return }  // can't match a real seq
    do { _ = try r.status.clear(seq: UInt32(seq)) } catch { throw fail() }
  }

  func registerBackgroundRefresh() throws {
    do { try scheduleRefresh() } catch { throw fail() }
  }

  /// The engine is going away: drop its claim (entries stay for the next drain).
  func detach() {
    claim.release(engineId)
    drainedLock.lock()
    drained.removeAll()
    drainedLock.unlock()
  }

  /// Ids this host may still ack (tests only).
  var ackableCount: Int {
    drainedLock.lock()
    defer { drainedLock.unlock() }
    return drained.count
  }
}

/// Registers the capture host on an engine (UI or headless). The host is
/// returned so the owner can `detach()` it when the engine goes away.
enum IosCaptureRegistration {
  @discardableResult
  static func register(
    with registry: FlutterPluginRegistry, key: String = "ZaghlolIosCapture",
    host: IosCaptureHost = IosCaptureHost()
  ) -> IosCaptureHost? {
    guard let registrar = registry.registrar(forPlugin: key) else { return nil }
    IosCaptureHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
    return host
  }

  /// Creates the Keychain spool key off the main thread at launch, so the
  /// first write from an extension or an App Intent doesn't pay the key
  /// creation (and its retry ladder).
  static func prepareKey() {
    DispatchQueue.global(qos: .utility).async {
      _ = SpoolRuntime.shared?.cipher.keyCreatedAtMs()
    }
  }
}
