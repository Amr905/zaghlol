import BackgroundTasks
import Flutter
import Foundation
import Security
import UserNotifications

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
  private let wipe: () throws -> Void
  private let drainHold: DrainHold
  private let stopHeadless: () -> Void
  private let intentRuns: () -> IntentRunLog?
  private let drainedLock = NSLock()
  private var drained = Set<String>()

  init(
    runtime: @escaping () -> SpoolRuntime? = { SpoolRuntime.shared },
    claim: SpoolClaim = .process,
    monoClockMs: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
    scheduleRefresh: @escaping () throws -> Void = { try IngestBackgroundRefresh.schedule() },
    guardRuntime: @escaping () -> GuardRuntime? = { CaptureGuardRuntime.shared },
    wipe: @escaping () throws -> Void = { try LocalDataWiper.wipeAll() },
    drainHold: DrainHold = .shared,
    stopHeadless: @escaping () -> Void = { Task { @MainActor in HeadlessIngestion.requestStop() } },
    intentRuns: @escaping () -> IntentRunLog? = { IntentCapture.productionRuns }
  ) {
    self.engineId = IosCaptureHost.newEngineId()
    self.runtime = runtime
    self.claim = claim
    self.monoClockMs = monoClockMs
    self.scheduleRefresh = scheduleRefresh
    self.guardRuntime = guardRuntime
    self.wipe = wipe
    self.drainHold = drainHold
    self.stopHeadless = stopHeadless
    self.intentRuns = intentRuns
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

  /// T-064: the per-intent last-run times the App Intents recorded. Times
  /// only; null = never (or not readable before the first unlock).
  func getShortcutSetupStatus() throws -> ShortcutSetupStatus {
    guard let log = intentRuns() else { throw fail(Self.notAvailable) }
    let r = log.read()
    return ShortcutSetupStatus(lastMessageIntentAtMs: r.messageAtMs, lastWalletIntentAtMs: r.walletAtMs)
  }

  func registerBackgroundRefresh() throws {
    do { try scheduleRefresh() } catch { throw fail() }
  }

  /// T-166 "Delete everything" (see `LocalDataWiper`). Any failure is a
  /// code-only `IO_ERROR`; the other parts still ran.
  func wipeLocalData() throws {
    drainedLock.lock()
    drained.removeAll()
    drainedLock.unlock()
    do { try wipe() } catch { throw fail() }
  }

  /// FU-194: sets or renews the restore's drain hold. A headless run still in
  /// progress is asked to stop (it closes the database before teardown);
  /// returns true while it is active. Does not need the spool.
  func holdDrain(ttlMs: Int64) throws -> Bool {
    let active: Bool
    do { active = try drainHold.hold(ttlMs: ttlMs) } catch { throw fail() }
    if active { stopHeadless() }
    return active
  }

  func isHeadlessDrainActive() throws -> Bool { drainHold.headlessActive() }

  func releaseDrainHold() throws {
    do { try drainHold.release() } catch { throw fail() }
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

/// T-166 "Delete everything", native part (design note in T-166.md, step 8).
/// Runs after Dart closed the database and deleted its key slots. Every part
/// runs even when an earlier one failed; `wipeAll` throws at the end if any
/// failed, so Dart keeps its resume marker. Directory roots are kept (only
/// their contents go) and their backup exclusion is applied again (T-165
/// F4). The seat keys (service `SeatKeyStore.service`) are never deleted
/// (D-55, R4-8). Nothing here logs.
enum LocalDataWiper {
  struct Incomplete: Error {}

  /// The Keychain service that survives the wipe.
  static let keptService = SeatKeyStore.service

  static func wipeAll() throws {
    var ok = true
    BGTaskScheduler.shared.cancelAllTaskRequests()
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
    ok = deleteKeychainItems() && ok
    let roots =
      ZaghlolDirectories.appContainerDirectories() + ZaghlolDirectories.appGroupDirectories()
    ok = wipeFiles(roots: roots) && ok
    if !ok { throw Incomplete() }
  }

  /// Clears the contents of every root, then re-applies the backup exclusion
  /// to every root (they must exist and stay excluded before the first-launch
  /// database is created). True when everything went.
  @discardableResult
  static func wipeFiles(roots: [URL], fileManager: FileManager = .default) -> Bool {
    var ok = true
    for root in roots {
      ok = clearContents(of: root, fileManager: fileManager) && ok
    }
    ok = ZaghlolDirectories.exclude(roots) && ok
    return ok
  }

  /// Deletes every entry inside `dir`, never `dir` itself. A symlink is
  /// removed as a link (its target is not followed). True when nothing is
  /// left or `dir` does not exist.
  static func clearContents(of dir: URL, fileManager: FileManager = .default) -> Bool {
    guard fileManager.fileExists(atPath: dir.path) else { return true }
    guard
      let entries = try? fileManager.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: [])
    else { return false }
    var ok = true
    for entry in entries {
      do {
        try fileManager.removeItem(at: entry)
      } catch {
        if fileManager.fileExists(atPath: entry.path) { ok = false }
      }
    }
    return ok
  }

  /// Whether a generic-password item with this service goes in the wipe.
  static func shouldDelete(service: String?) -> Bool { service != keptService }

  /// Deletes every Keychain item of the app's access groups except the seat
  /// keys. Generic passwords are deleted one by one by persistent reference,
  /// so a query can never widen to a seat-key item.
  static func deleteKeychainItems() -> Bool {
    var ok = true
    for cls in [kSecClassInternetPassword, kSecClassCertificate, kSecClassKey, kSecClassIdentity] {
      let status = SecItemDelete(
        [
          kSecClass as String: cls,
          kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ] as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound { ok = false }
    }
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true,
        kSecReturnPersistentRef as String: true,
      ] as CFDictionary, &result)
    if status == errSecItemNotFound { return ok }
    guard status == errSecSuccess, let items = result as? [[String: Any]] else { return false }
    for item in items {
      if !shouldDelete(service: item[kSecAttrService as String] as? String) { continue }
      guard let ref = item[kSecValuePersistentRef as String] as? Data else {
        ok = false
        continue
      }
      let deleted = SecItemDelete(
        [
          kSecClass as String: kSecClassGenericPassword,
          kSecValuePersistentRef as String: ref,
        ] as CFDictionary)
      if deleted != errSecSuccess && deleted != errSecItemNotFound { ok = false }
    }
    return ok
  }
}
