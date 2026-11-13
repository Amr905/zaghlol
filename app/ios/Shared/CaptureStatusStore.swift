import Foundation

/// Alert counters of the capture path (T-039 design note 5, mirrored by T-062).
/// Counts are unsigned 32-bit and saturate; times are wall-clock ms, -1 = none.
/// Holds no message content.
struct CaptureStatus: Equatable {
  var seq: UInt32 = 0
  var refusedFull: UInt32 = 0
  var refusedGeneric: UInt32 = 0
  var rateLimited: UInt32 = 0
  var missedNotifications: UInt32 = 0
  var firstMissedSmsAtMs: Int64 = -1
  var lastRefusedAtMs: Int64 = -1
  var decryptDeleted: UInt32 = 0
  var keyInvalidatedAtMs: Int64 = -1
}

/// The status file can't be read now (I/O or Keychain); nothing was overwritten.
struct CaptureStatusUnavailable: Error {}

/// `<container>/Library/Application Support/capture/status.bin`: AES-GCM with
/// the spool key, AAD `zaghlol.capture.v1|status`, the same fixed binary
/// record v1 as Android. Written only on an alert and on `clear`; never for a
/// normal keep or a non-financial drop.
///
/// Failure rules (self-check 1): absent file = zeros; tag failure or malformed
/// on every attempt (100/300/900 ms) = restart from zero with
/// `keyInvalidatedAtMs = now` and a fresh random `seq`; an I/O or Keychain
/// error keeps the alert in memory as a pending delta and never overwrites
/// the unread file.
///
/// Coalescing (T-040 design note 8): an alert that adds a fact the file does
/// not hold yet is written at once; any other alert is written only when no
/// write succeeded in the last 10 s (monotonic), else it stays in the
/// in-memory delta, merged by the next `read`/`clear` or the next alert after
/// the window. A process kill loses at most the counts of one window.
///
/// Two processes (app, extensions) update this file, so every read-modify-write
/// runs under an exclusive `flock` on `status.lock` next to it.
final class CaptureStatusStore {
  static let version: UInt8 = 1
  static let coalesceWindowMs: Int64 = 10_000
  static let channelSms = "sms"
  static let channelNotification = "notification"
  static let recordBytes = 1 + 4 * 5 + 8 + 8 + 4 + 8
  static let maxFileBytes = 1024
  static let aad = Data("zaghlol.capture.v1|status".utf8)
  static let retryDelaysMs: [UInt32] = [0, 100, 300, 900]

  private struct Delta {
    var changes: UInt32 = 0
    var refusedFull: UInt64 = 0
    var refusedGeneric: UInt64 = 0
    var rateLimited: UInt64 = 0
    var missedNotifications: UInt64 = 0
    var firstMissedSms: Int64 = -1
    var lastRefusedAtMs: Int64 = -1
    var decryptDeleted: UInt64 = 0
    var keyInvalidated: Int64 = -1

    func addsFact(to d: CaptureStatus) -> Bool {
      (refusedFull > 0 && d.refusedFull == 0) || (refusedGeneric > 0 && d.refusedGeneric == 0)
        || (rateLimited > 0 && d.rateLimited == 0)
        || (missedNotifications > 0 && d.missedNotifications == 0)
        || (firstMissedSms >= 0
          && (d.firstMissedSmsAtMs < 0 || firstMissedSms < d.firstMissedSmsAtMs))
        || (decryptDeleted > 0 && d.decryptDeleted == 0)
        || (keyInvalidated >= 0
          && (d.keyInvalidatedAtMs < 0 || keyInvalidated < d.keyInvalidatedAtMs))
    }

    mutating func missed(_ channel: String, _ wallMs: Int64) {
      switch channel {
      case CaptureStatusStore.channelSms: firstMissedSms = earliest(firstMissedSms, wallMs)
      case CaptureStatusStore.channelNotification: missedNotifications += 1
      default: break
      }
    }

    func applied(to s: CaptureStatus) -> CaptureStatus {
      var o = s
      o.seq = UInt32(truncatingIfNeeded: UInt64(s.seq) + UInt64(changes))
      o.refusedFull = sat(UInt64(s.refusedFull) + refusedFull)
      o.refusedGeneric = sat(UInt64(s.refusedGeneric) + refusedGeneric)
      o.rateLimited = sat(UInt64(s.rateLimited) + rateLimited)
      o.missedNotifications = sat(UInt64(s.missedNotifications) + missedNotifications)
      o.firstMissedSmsAtMs = earliest(s.firstMissedSmsAtMs, firstMissedSms)
      o.lastRefusedAtMs = max(s.lastRefusedAtMs, lastRefusedAtMs)
      o.decryptDeleted = sat(UInt64(s.decryptDeleted) + decryptDeleted)
      o.keyInvalidatedAtMs = earliest(s.keyInvalidatedAtMs, keyInvalidated)
      return o
    }
  }

  private final class Shared {
    let lock = NSLock()
    var pending = Delta()
    var onDisk: CaptureStatus?
    var lastWriteMono: Int64?
  }
  private static let registry = NSLock()
  private static var shared: [String: Shared] = [:]

  private let file: URL
  private let cipher: SpoolCipher
  private let sleeper: (UInt32) -> Void
  private let wallClock: () -> Int64
  private let files: SpoolFileOps
  private let randomSeq: () -> UInt32
  private let monoClockMs: () -> Int64
  private let excludeDir: (URL) throws -> Void
  private let state: Shared

  init(
    file: URL, cipher: SpoolCipher, sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) },
    wallClock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    files: SpoolFileOps = DefaultSpoolFileOps(),
    randomSeq: @escaping () -> UInt32 = { UInt32.random(in: 0...UInt32.max) },
    monoClockMs: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
    excludeDir: @escaping (URL) throws -> Void = ZaghlolDirectories.ensureExcluded
  ) {
    self.file = file
    self.cipher = cipher
    self.sleeper = sleeper
    self.wallClock = wallClock
    self.files = files
    self.randomSeq = randomSeq
    self.monoClockMs = monoClockMs
    self.excludeDir = excludeDir
    let key = file.standardizedFileURL.resolvingSymlinksInPath().path
    CaptureStatusStore.registry.lock()
    if let s = CaptureStatusStore.shared[key] {
      state = s
    } else {
      let s = Shared()
      CaptureStatusStore.shared[key] = s
      state = s
    }
    CaptureStatusStore.registry.unlock()
  }

  // MARK: Alerts

  func recordRefused(_ reason: SpoolRefusal, channel: String, wallMs: Int64) {
    record {
      switch reason {
      case .full, .smsReserve: $0.refusedFull += 1
      case .genericBudget, .genericRate: $0.refusedGeneric += 1
      }
      $0.lastRefusedAtMs = max($0.lastRefusedAtMs, wallMs)
      $0.missed(channel, wallMs)
    }
  }

  func recordRateLimited(channel: String, wallMs: Int64) {
    record {
      $0.rateLimited += 1
      $0.missed(channel, wallMs)
    }
  }

  func recordKeyInvalidated(wallMs: Int64) {
    record { $0.keyInvalidated = earliest($0.keyInvalidated, wallMs) }
  }

  /// The alerts of one drain, recorded with one status write (none when the drain found nothing).
  func recordDrain(_ scope: SpoolDrainScope) {
    guard scope.decryptDeleted > 0 || scope.keyInvalidatedAtMs >= 0 else { return }
    record {
      $0.decryptDeleted += UInt64(scope.decryptDeleted)
      if scope.keyInvalidatedAtMs >= 0 {
        $0.keyInvalidated = earliest($0.keyInvalidated, scope.keyInvalidatedAtMs)
      }
    }
  }

  /// The current status with pending alerts merged. Throws `CaptureStatusUnavailable`.
  func read() throws -> CaptureStatus {
    state.lock.lock()
    defer { state.lock.unlock() }
    return try withFileLock { try mergedLocked() }
  }

  /// Compare-and-clear: zeroes the counters if `seq` is still current.
  func clear(seq: UInt32) throws -> Bool {
    state.lock.lock()
    defer { state.lock.unlock() }
    return try withFileLock {
      let current = try mergedLocked()
      guard current.seq == seq else { return false }
      var next = CaptureStatus()
      next.seq = current.seq &+ 1
      try writeLocked(next)
      state.pending = Delta()
      return true
    }
  }

  private func record(_ change: (inout Delta) -> Void) {
    state.lock.lock()
    defer { state.lock.unlock() }
    change(&state.pending)
    state.pending.changes += 1
    if let disk = state.onDisk, let last = state.lastWriteMono, !state.pending.addsFact(to: disk) {
      let age = monoClockMs() - last
      if age >= 0 && age < Self.coalesceWindowMs { return }
    }
    _ = try? withFileLock { try mergedLocked() }  // kept in memory when it fails
  }

  // MARK: File

  private func withFileLock<T>(_ body: () throws -> T) throws -> T {
    let dir = file.deletingLastPathComponent()
    do { try excludeDir(dir) } catch { throw CaptureStatusUnavailable() }
    let fd = open(dir.appendingPathComponent("status.lock").path, O_RDWR | O_CREAT, 0o600)
    guard fd >= 0 else { throw CaptureStatusUnavailable() }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw CaptureStatusUnavailable() }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }

  private enum Loaded {
    case absent, ok(CaptureStatus), unreadable, unavailable
  }

  private func mergedLocked() throws -> CaptureStatus {
    let base: CaptureStatus
    var mustWrite = false
    switch loadLocked() {
    case .absent: base = CaptureStatus()
    case .ok(let s): base = s
    case .unreadable:
      var s = CaptureStatus()
      s.seq = randomSeq()
      s.keyInvalidatedAtMs = wallClock()
      base = s
      mustWrite = true
    case .unavailable: throw CaptureStatusUnavailable()
    }
    if state.pending.changes == 0 && !mustWrite {
      state.onDisk = base
      return base
    }
    let next = state.pending.changes == 0 ? base : state.pending.applied(to: base)
    do {
      try writeLocked(next)
      state.pending = Delta()
    } catch {
      state.onDisk = mustWrite ? nil : base  // file unchanged; the delta stays pending
    }
    return next
  }

  private func loadLocked() -> Loaded {
    for (attempt, delay) in Self.retryDelaysMs.enumerated() {
      if attempt > 0 { sleeper(delay) }
      var st = stat()
      if lstat(file.path, &st) != 0 {
        return errno == ENOENT ? .absent : .unavailable
      }
      if Int(st.st_size) > Self.maxFileBytes { continue }  // proof
      guard let bytes = try? Data(contentsOf: file) else { return .unavailable }
      if bytes.count < SpoolStoreConstants.nonceBytes + SpoolStoreConstants.tagBytes { continue }
      do {
        return .ok(try Self.decode(try cipher.decrypt(bytes, aad: Self.aad)))
      } catch SpoolCipherError.notAuthentic {
        // proof; retry per schedule
      } catch is SpoolFormatError {
        // proof; retry per schedule
      } catch {
        return .unavailable  // Keychain: proves nothing
      }
    }
    return .unreadable
  }

  private func writeLocked(_ s: CaptureStatus) throws {
    let dir = file.deletingLastPathComponent()
    let sealed = try cipher.encrypt(Self.encode(s), aad: Self.aad)
    let tmp = dir.appendingPathComponent(file.lastPathComponent + SpoolStore.tmpSuffix)
    unlink(tmp.path)  // a leftover of a killed write; we hold the file lock
    do {
      try files.create(tmp, contents: sealed)
      try files.move(tmp, file)
    } catch {
      unlink(tmp.path)
      throw error
    }
    files.syncDir(dir)
    state.onDisk = s
    state.lastWriteMono = monoClockMs()
  }

  // MARK: Record

  /// `u8 v=1 | seq u32 | refusedFull u32 | refusedGeneric u32 | rateLimited u32 |
  ///  missedNotifications u32 | firstMissedSmsAtMs i64 | lastRefusedAtMs i64 |
  ///  decryptDeleted u32 | keyInvalidatedAtMs i64` (big-endian).
  static func encode(_ s: CaptureStatus) -> Data {
    var out = Data([version])
    func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.bigEndian) { out.append(contentsOf: $0) } }
    put(s.seq)
    put(s.refusedFull)
    put(s.refusedGeneric)
    put(s.rateLimited)
    put(s.missedNotifications)
    put(s.firstMissedSmsAtMs)
    put(s.lastRefusedAtMs)
    put(s.decryptDeleted)
    put(s.keyInvalidatedAtMs)
    return out
  }

  static func decode(_ data: Data) throws -> CaptureStatus {
    guard data.count == recordBytes, data.first == version else { throw SpoolFormatError() }
    let b = [UInt8](data)
    var pos = 1
    func u32() -> UInt32 {
      defer { pos += 4 }
      return b[pos..<pos + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    func i64() -> Int64 {
      defer { pos += 8 }
      return Int64(bitPattern: b[pos..<pos + 8].reduce(0) { ($0 << 8) | UInt64($1) })
    }
    var s = CaptureStatus()
    s.seq = u32()
    s.refusedFull = u32()
    s.refusedGeneric = u32()
    s.rateLimited = u32()
    s.missedNotifications = u32()
    s.firstMissedSmsAtMs = i64()
    s.lastRefusedAtMs = i64()
    s.decryptDeleted = u32()
    s.keyInvalidatedAtMs = i64()
    guard s.firstMissedSmsAtMs >= -1, s.lastRefusedAtMs >= -1, s.keyInvalidatedAtMs >= -1 else {
      throw SpoolFormatError()
    }
    return s
  }
}

private func sat(_ v: UInt64) -> UInt32 { v > UInt64(UInt32.max) ? UInt32.max : UInt32(v) }

private func earliest(_ a: Int64, _ b: Int64) -> Int64 {
  if a < 0 { return b }
  if b < 0 { return a }
  return min(a, b)
}
