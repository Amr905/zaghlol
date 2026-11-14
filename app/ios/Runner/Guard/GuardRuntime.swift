import Foundation

/// State of the user part as the runtime last saw it (surfaced to Dart as the
/// `GuardConfigState`).
enum GuardUserState {
  /// No user file (fresh install).
  case absent
  /// Decrypted and parsed.
  case ok
  /// Proven unusable (authentication failure, malformed, unknown version);
  /// kept until the next successful write.
  case unreadable
  /// I/O or Keychain error this time; retried on the next message.
  case retry
}

/// The rules one message is decided with. Immutable; `description` prints
/// mode and state only.
final class GuardSnapshot: CustomStringConvertible {
  let guardRules: CaptureGuard
  let mode: GuardConfigMode
  let userState: GuardUserState

  init(guardRules: CaptureGuard, mode: GuardConfigMode, userState: GuardUserState) {
    self.guardRules = guardRules
    self.mode = mode
    self.userState = userState
  }

  var description: String { "GuardSnapshot(\(mode.rawValue), \(userState))" }
}

/// The process-wide Guard (Swift port of Kotlin `GuardRuntime`, T-038 design
/// note sections 4 to 6): lazily loads the bundled base part and the
/// encrypted user part, decides messages with the per-process
/// `SenderRateLimiter`, and replaces the user part.
///
/// Caching: a valid base with an absent, valid or proven-unreadable user part
/// is cached; an invalid base (build defect, or a transient read error) and a
/// transient user-file error are not, so the next message retries. One lock
/// serializes loads and writes; a message decided during a write uses the old
/// or the new rules, never a mix (the snapshot is immutable).
final class GuardRuntime {
  private let loadBase: () throws -> Data
  private let store: GuardUserConfigStore
  private let clockMs: () -> Int64
  private let parse: (Data, Data?, Bool) -> GuardConfigLoad
  private let lock = NSLock()
  private var snapshot: GuardSnapshot?
  /// Bytes of the last base that parsed (public registry data).
  private var validBase: Data?
  /// The compiled base-only rules of `validBase`: a transient user-file error
  /// is not cached as a snapshot, but reuses these instead of compiling the
  /// base again per message.
  private var baseOnly: GuardConfigLoad?
  private var limiter: SenderRateLimiter?

  private static let invalidSnapshot = GuardSnapshot(
    guardRules: CaptureGuard(config: nil), mode: .invalid, userState: .retry)

  init(
    loadBase: @escaping () throws -> Data,
    store: GuardUserConfigStore,
    clockMs: @escaping () -> Int64 = GuardRuntime.monotonicMs,
    parse: @escaping (Data, Data?, Bool) -> GuardConfigLoad = {
      GuardConfig.parse(base: $0, user: $1, userUnreadable: $2)
    }
  ) {
    self.loadBase = loadBase
    self.store = store
    self.clockMs = clockMs
    self.parse = parse
  }

  /// Monotonic milliseconds (the rate window only compares differences).
  static func monotonicMs() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

  /// The rules to use now. Never throws.
  func current() -> GuardSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return currentLocked()
  }

  /// Mode and user state now (loads on first use).
  func state() -> GuardSnapshot { current() }

  /// Guard decision plus the per-process rate limit (applied to keeps only).
  /// Never throws. Typed: only the iOS capture channels reach the native Guard.
  func decide(channel: IosGuardChannel, source: String, body: String) -> GuardDecision {
    let snap = current()
    let wire = channel.channel.wire
    let decision = snap.guardRules.decide(channel: wire, source: source, body: body)
    guard let cfg = snap.guardRules.config else { return decision }
    return limiterFor(cfg.perSenderPerMin).apply(
      decision, channel: wire, source: source, nowMs: clockMs())
  }

  /// Replaces the user part (host `writeGuardConfig`). Under the runtime
  /// lock: size and full reader validation before anything is written; then
  /// encrypt + tmp + fsync + rename; then the new snapshot is published. On
  /// any failure the previous file and snapshot stay in force.
  ///
  /// The caller owns `json` and should drop its reference right after.
  func writeUser(_ json: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    if json.count > GuardConfig.maxUserBytes {
      throw GuardConfigWriteError(
        .configInvalid, detail: GuardConfigError(code: .tooLarge, path: "$"))
    }
    if let e = GuardConfig.validateUser(json) {
      throw GuardConfigWriteError(.configInvalid, detail: e)
    }
    try store.write(json)
    if let base = validBase {
      snapshot = GuardRuntime.snapshotOf(parse(base, json, false), .ok)
    } else {
      // Base not loaded yet (or invalid): the next message loads both parts.
      snapshot = nil
    }
  }

  // MARK: Private

  private func currentLocked() -> GuardSnapshot {
    if let s = snapshot { return s }
    return load()
  }

  private func load() -> GuardSnapshot {
    let base: Data
    if let b = validBase {
      base = b
    } else {
      do {
        base = try loadBase()
      } catch {
        return GuardRuntime.invalidSnapshot
      }
    }
    let result: GuardConfigLoad
    let userState: GuardUserState
    var transient = false
    switch store.read() {
    case .absent:
      result = baseOnlyOf(base)
      userState = .absent
    case .plain(let bytes):
      result = parse(base, bytes, false)
      userState = result.userFailed ? .unreadable : .ok
    case .unreadable:
      result = parse(base, nil, true)
      userState = .unreadable
    case .transient:
      // Not cached as a snapshot (the next message retries the file), but the
      // compiled base-only rules are reused.
      result = baseOnlyOf(base)
      userState = .retry
      transient = true
    }
    let snap = GuardRuntime.snapshotOf(result, userState)
    if result.baseError == nil {
      validBase = base
      if !transient { snapshot = snap }
    }
    return snap
  }

  /// T-166: forgets every cached rule and the rate limiter ("Delete
  /// everything" removed the user part and its key); the next message loads
  /// again.
  func reset() {
    lock.lock()
    snapshot = nil
    validBase = nil
    baseOnly = nil
    limiter = nil
    lock.unlock()
  }

  /// The base-only rules of `base`, parsed once per valid base.
  private func baseOnlyOf(_ base: Data) -> GuardConfigLoad {
    if let cached = baseOnly, validBase == base { return cached }
    let load = parse(base, nil, false)
    if load.baseError == nil { baseOnly = load }
    return load
  }

  private func limiterFor(_ perMin: Int) -> SenderRateLimiter {
    lock.lock()
    defer { lock.unlock() }
    if let l = limiter, l.perSenderPerMin == perMin { return l }
    let l = SenderRateLimiter(perSenderPerMin: perMin)
    limiter = l
    return l
  }

  private static func snapshotOf(_ load: GuardConfigLoad, _ userState: GuardUserState)
    -> GuardSnapshot
  {
    GuardSnapshot(guardRules: CaptureGuard(config: load.config), mode: load.mode, userState: userState)
  }
}
