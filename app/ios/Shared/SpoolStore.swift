import Foundation

/// Which share of the spool a write may use (T-039 design note 4). The Guard's
/// keep kind maps here: `registry` / `user` -> priority, `generic` -> generic.
/// Never written to disk (a per-kind file name would leak the content class).
enum SpoolAdmissionClass { case priority, generic }

/// Why a write was refused. Old entries are never evicted for a new one.
enum SpoolRefusal: Equatable {
  case full  // 500 entries or 4 MiB on disk
  case genericBudget  // a generic keep while the spool holds half its caps
  case genericRate  // too many generic writes in the window (per process)
  case smsReserve  // an `sms` keep while the spool holds its 80 % share (never on iOS)
}

/// Caps of the spool: the Android numbers (platform-channels.md 1.3), same
/// provisional status (PO Q1 of T-039/T-040). Tests shrink them.
struct SpoolLimits {
  var maxEntries = 500
  var maxBytes: Int64 = 4 * 1024 * 1024
  var genericMaxEntries = 250
  var genericMaxBytes: Int64 = 2 * 1024 * 1024
  var genericPerWindow = 10
  var genericWindowMs: Int64 = 60_000
  var maxHeld = 50
  var smsMaxEntries = 400
  var smsMaxBytes: Int64 = 4 * 1024 * 1024 * 80 / 100
}

enum SpoolWriteResult: Equatable {
  case written(String)
  case refused(SpoolRefusal)
}

enum SpoolReadResult {
  case ok(SpoolRecord)
  /// Proven not authentic; the entry was deleted.
  case deleted
  /// Already gone (acked or deleted meanwhile).
  case missing
  /// Could not be read now; the entry is kept. `keyRelated`: the cipher or
  /// Keychain failed (not the file), so the next entries would fail the same way.
  case unavailable(keyRelated: Bool)
}

/// Alerts found by the reads of one drain, written to the capture status once.
final class SpoolDrainScope {
  var decryptDeleted = 0
  var keyInvalidatedAtMs: Int64 = -1
  func keyInvalidated(_ wallMs: Int64) {
    if keyInvalidatedAtMs < 0 || wallMs < keyInvalidatedAtMs { keyInvalidatedAtMs = wallMs }
  }
}

/// The file steps of an atomic write behind a seam, so tests inject a fault at
/// every step (including "process dies between fsync and rename").
protocol SpoolFileOps {
  func create(_ url: URL, contents: Data) throws  // exclusive create, write, full fsync, protection class
  func move(_ from: URL, _ to: URL) throws  // atomic rename, replaces nothing (fresh ULID)
  func syncDir(_ dir: URL)  // best effort
}

struct DefaultSpoolFileOps: SpoolFileOps {
  struct Failure: Error { let errnoValue: Int32 }

  func create(_ url: URL, contents: Data) throws {
    let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    if fd < 0 { throw Failure(errnoValue: errno) }
    var ok = false
    defer {
      close(fd)
      if !ok { unlink(url.path) }
    }
    try contents.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
        if n < 0 {
          if errno == EINTR { continue }
          throw Failure(errnoValue: errno)
        }
        offset += n
      }
    }
    if fcntl(fd, F_FULLFSYNC) != 0 && fsync(fd) != 0 { throw Failure(errnoValue: errno) }
    // Readable by the app and the extensions after the first unlock, the same
    // availability as the Keychain key (a locked-device read cannot decrypt anyway).
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
    ok = true
  }

  func move(_ from: URL, _ to: URL) throws {
    if rename(from.path, to.path) != 0 { throw Failure(errnoValue: errno) }
  }

  func syncDir(_ dir: URL) {
    let fd = open(dir.path, O_RDONLY)
    if fd >= 0 {
      _ = fsync(fd)
      close(fd)
    }
  }
}

/// The encrypted spool (platform-channels.md 1.3, ADR-005). Directory
/// `<App Group container>/spool/`, one file per message, `<ulid>.bin` =
/// AES-GCM(record) with AAD `zaghlol.spool.v1|entry|<ulid>`. Same rules as
/// the Android `SpoolStore`:
///
/// - At-least-once: an entry is deleted only by `ack` (the host scopes acks
///   to what its engine drained) or on proof that it is not authentic. I/O
///   and Keychain errors never delete. No age purge.
/// - Admission: full caps, the sms share, a half-spool budget and a
///   per-minute rate for generic keeps; refusals are recorded in the capture
///   status; old entries are never evicted.
/// - No spool-level dedupe (the DB's `body_hash` is the only one).
/// - File names are a ULID only.
///
/// Two processes write here (the app and the extensions), so the in-process
/// lock is not enough: an entry is complete or absent by `.tmp` + fsync +
/// atomic rename; the caps may overshoot by the writes in flight; and
/// `sweepTmp` removes only `.tmp` files older than `tmpMaxAgeS` (a younger
/// one may be another process's write in flight).
final class SpoolStore {
  static let tmpSuffix = ".tmp"
  static let heldDir = "held"
  static let heldVersionFile = ".app_version"
  static let retryDelaysMs: [UInt32] = [0, 100, 300, 900]
  static let tmpMaxAgeS: TimeInterval = 600

  let dir: URL
  private let cipher: SpoolCipher
  private let status: CaptureStatusStore?
  private let ids: SpoolUlidGenerator
  private let wallClock: () -> Int64
  private let monoClockMs: () -> Int64
  private let sleeper: (UInt32) -> Void
  private let files: SpoolFileOps
  private let limits: SpoolLimits
  private let excludeDir: (URL) throws -> Void

  private final class Shared {
    let lock = NSLock()
    var genericWrites: [Int64] = []
    var ensured = false
    var appVersion: String?
  }
  private static let registry = NSLock()
  private static var shared: [String: Shared] = [:]
  private let state: Shared

  init(
    dir: URL, cipher: SpoolCipher, status: CaptureStatusStore? = nil,
    ids: SpoolUlidGenerator = SpoolUlidGenerator(),
    wallClock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    monoClockMs: @escaping () -> Int64 = {
      Int64(ProcessInfo.processInfo.systemUptime * 1000)
    },
    sleeper: @escaping (UInt32) -> Void = { usleep($0 * 1000) },
    files: SpoolFileOps = DefaultSpoolFileOps(), limits: SpoolLimits = SpoolLimits(),
    excludeDir: @escaping (URL) throws -> Void = ZaghlolDirectories.ensureExcluded
  ) {
    self.dir = dir
    self.cipher = cipher
    self.status = status
    self.ids = ids
    self.wallClock = wallClock
    self.monoClockMs = monoClockMs
    self.sleeper = sleeper
    self.files = files
    self.limits = limits
    self.excludeDir = excludeDir
    let key = dir.standardizedFileURL.resolvingSymlinksInPath().path
    SpoolStore.registry.lock()
    if let s = SpoolStore.shared[key] {
      state = s
    } else {
      let s = Shared()
      SpoolStore.shared[key] = s
      state = s
    }
    SpoolStore.registry.unlock()
  }

  static func aad(_ id: String) -> Data { Data("zaghlol.spool.v1|entry|\(id)".utf8) }

  static func isEntryName(_ name: String) -> Bool {
    name.count == 30 && name.hasSuffix(".bin") && SpoolUlidGenerator.isValid(String(name.prefix(26)))
  }

  static func isTmpName(_ name: String) -> Bool {
    name.count == 34 && name.hasSuffix(".bin" + tmpSuffix)
      && SpoolUlidGenerator.isValid(String(name.prefix(26)))
  }

  private func entry(_ id: String) -> URL { dir.appendingPathComponent("\(id).bin") }
  private var held: URL { dir.appendingPathComponent(Self.heldDir, isDirectory: true) }

  /// True only when the path positively does not exist (`ENOENT`).
  static func isProvenAbsent(_ url: URL) -> Bool {
    var st = stat()
    return lstat(url.path, &st) != 0 && errno == ENOENT
  }

  private func listing(_ url: URL) -> [String]? {
    try? FileManager.default.contentsOfDirectory(atPath: url.path)
  }

  private func size(_ url: URL) -> Int64 {
    var st = stat()
    return lstat(url.path, &st) == 0 ? Int64(st.st_size) : 0
  }

  // MARK: Write

  /// Admits, encrypts and writes `record` atomically. Returns `.refused` when
  /// the admission rules say no (recorded in the capture status). Throws when
  /// the write itself fails; nothing is left behind except possibly a `.tmp`.
  func write(_ record: SpoolRecord, cls: SpoolAdmissionClass) throws -> SpoolWriteResult {
    var plain = try SpoolRecordCodec.encode(record)
    defer { Self.zero(&plain) }
    state.lock.lock()
    defer { state.lock.unlock() }
    // Every writer creates its own target directory excluded (T-165 F5).
    if !state.ensured || SpoolStore.isProvenAbsent(dir) {
      try excludeDir(dir)
      state.ensured = true
    }
    guard let listed = listing(dir) else { throw SpoolIOError.listing }
    var n = 0
    var bytes: Int64 = 0
    for name in listed where Self.isEntryName(name) || Self.isTmpName(name) {
      n += 1
      bytes += size(dir.appendingPathComponent(name))
    }
    if !SpoolStore.isProvenAbsent(held) {
      guard let h = listing(held) else { throw SpoolIOError.listing }
      for name in h where Self.isEntryName(name) {
        n += 1
        bytes += size(held.appendingPathComponent(name))
      }
    }
    let after = bytes + Int64(plain.count + SpoolStoreConstants.nonceBytes + SpoolStoreConstants.tagBytes)
    let now = monoClockMs()
    let reason: SpoolRefusal?
    if n >= limits.maxEntries || after > limits.maxBytes {
      reason = .full
    } else if record.channel == CaptureStatusStore.channelSms
      && (n >= limits.smsMaxEntries || after > limits.smsMaxBytes)
    {
      reason = .smsReserve
    } else if cls == .generic && (n >= limits.genericMaxEntries || after > limits.genericMaxBytes) {
      reason = .genericBudget
    } else if cls == .generic && recentGenericWrites(now) >= limits.genericPerWindow {
      reason = .genericRate
    } else {
      reason = nil
    }
    if let reason = reason {
      status?.recordRefused(reason, channel: record.channel, wallMs: wallClock())
      return .refused(reason)
    }
    let id = ids.next()
    let sealed = try cipher.encrypt(plain, aad: Self.aad(id))
    let tmp = dir.appendingPathComponent("\(id).bin\(Self.tmpSuffix)")
    do {
      try files.create(tmp, contents: sealed)
      try files.move(tmp, entry(id))
    } catch {
      unlink(tmp.path)
      throw error
    }
    files.syncDir(dir)
    if cls == .generic { state.genericWrites.append(now) }
    return .written(id)
  }

  private func recentGenericWrites(_ now: Int64) -> Int {
    state.genericWrites.removeAll { now - $0 >= limits.genericWindowMs }
    return state.genericWrites.count
  }

  private static func zero(_ data: inout Data) {
    data.withUnsafeMutableBytes { raw in
      if let base = raw.baseAddress { memset_s(base, raw.count, 0, raw.count) }
    }
  }

  // MARK: Listing

  /// Pending entry ids, oldest first. Foreign names and held entries are ignored.
  func pendingIds() -> [String] {
    (listing(dir) ?? []).filter(Self.isEntryName).map { String($0.dropLast(4)) }.sorted()
  }

  func pendingCount() -> Int { pendingIds().count }

  /// Pending entries, or nil when the directory can't be listed now ("unknown"
  /// is never "empty").
  func pendingCountOrNil() -> Int? {
    guard let names = listing(dir) else { return Self.isProvenAbsent(dir) ? 0 : nil }
    return names.filter(Self.isEntryName).count
  }

  func heldCount() -> Int { (listing(held) ?? []).filter(Self.isEntryName).count }

  // MARK: Hold / release

  /// Moves a drained entry the use case could not store even alone to
  /// `spool/held/` (same bytes, so the AAD still matches). False (nothing
  /// changed) for an invalid id, a gone entry or a full held area.
  func hold(_ id: String) throws -> Bool {
    guard SpoolUlidGenerator.isValid(id) else { return false }
    state.lock.lock()
    defer { state.lock.unlock() }
    if Self.isProvenAbsent(entry(id)) { return false }
    try FileManager.default.createDirectory(at: held, withIntermediateDirectories: true)
    guard let h = listing(held) else { throw SpoolIOError.listing }
    if h.filter(Self.isEntryName).count >= limits.maxHeld { return false }
    if let v = state.appVersion, Self.isProvenAbsent(held.appendingPathComponent(Self.heldVersionFile)) {
      writeHeldVersion(v)
    }
    try files.move(entry(id), held.appendingPathComponent("\(id).bin"))
    files.syncDir(dir)
    files.syncDir(held)
    return true
  }

  /// Called once per process start with the running build: when it differs
  /// from `held/.app_version`, every held entry goes back to the spool (an
  /// update may fix the cause). Never deletes. Returns the number released.
  @discardableResult
  func releaseHeldIfVersionChanged(appVersion: String) -> Int {
    state.lock.lock()
    defer { state.lock.unlock() }
    state.appVersion = appVersion
    guard !Self.isProvenAbsent(held) else { return 0 }
    let versionFile = held.appendingPathComponent(Self.heldVersionFile)
    var stored: String?
    if !Self.isProvenAbsent(versionFile) {
      guard let data = try? Data(contentsOf: versionFile) else { return 0 }  // can't tell: stay held
      stored = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if stored == appVersion { return 0 }
    guard let names = listing(held) else { return 0 }
    var released = 0
    for name in names.filter(Self.isEntryName) {
      do {
        try files.move(held.appendingPathComponent(name), dir.appendingPathComponent(name))
        released += 1
      } catch { return released }
    }
    files.syncDir(dir)
    writeHeldVersion(appVersion)
    return released
  }

  private func writeHeldVersion(_ v: String) {
    let tmp = held.appendingPathComponent(Self.heldVersionFile + Self.tmpSuffix)
    do {
      try files.create(tmp, contents: Data(v.utf8))
      try files.move(tmp, held.appendingPathComponent(Self.heldVersionFile))
    } catch { unlink(tmp.path) }
  }

  // MARK: Read

  /// Reads and decrypts one entry. Not authentic (tag failure, truncation,
  /// malformed record) is retried at 100/300/900 ms; only when every attempt
  /// proves it bad is the entry deleted. Any other failure keeps it.
  ///
  /// Lost key: when the first attempt fails the tag of a full-length entry
  /// whose ULID time precedes the current key's creation, it was written
  /// under an earlier key: deleted at once and `keyInvalidatedAtMs` recorded.
  func read(_ id: String, scope: SpoolDrainScope? = nil) -> SpoolReadResult {
    guard SpoolUlidGenerator.isValid(id) else { return .missing }
    var transient = false
    var keyRelated = false
    for (attempt, delay) in Self.retryDelaysMs.enumerated() {
      if attempt > 0 { sleeper(delay) }
      let bytes: Data?
      switch readBounded(entry(id)) {
      case .absent: return .missing
      case .failed:
        transient = true
        continue
      case .tooLarge: bytes = nil  // proof: not a record we wrote
      case .data(let d): bytes = d
      }
      guard let data = bytes, data.count >= SpoolStoreConstants.nonceBytes + SpoolStoreConstants.tagBytes
      else { continue }  // proof
      do {
        var plain = try cipher.decrypt(data, aad: Self.aad(id))
        defer { Self.zero(&plain) }
        return .ok(try SpoolRecordCodec.decode(plain))
      } catch SpoolCipherError.notAuthentic {
        if attempt == 0 && !transient && writtenBeforeCurrentKey(id) {
          if let scope = scope { scope.keyInvalidated(wallClock()) } else {
            status?.recordKeyInvalidated(wallMs: wallClock())
          }
          return deleteOnProof(id, scope)
        }
      } catch is SpoolFormatError {
        // proof; retry per schedule
      } catch {
        transient = true
        keyRelated = true
      }
    }
    if transient { return .unavailable(keyRelated: keyRelated) }
    return deleteOnProof(id, scope)
  }

  private func writtenBeforeCurrentKey(_ id: String) -> Bool {
    guard let created = cipher.keyCreatedAtMs(), let t = SpoolUlidGenerator.timeMs(id) else {
      return false
    }
    return t < created
  }

  private func deleteOnProof(_ id: String, _ scope: SpoolDrainScope?) -> SpoolReadResult {
    let url = entry(id)
    if unlink(url.path) == 0 {
      scope?.decryptDeleted += 1
      return .deleted
    }
    return Self.isProvenAbsent(url) ? .missing : .unavailable(keyRelated: false)
  }

  private enum Bounded {
    case data(Data), absent, failed, tooLarge
  }

  private func readBounded(_ url: URL) -> Bounded {
    var st = stat()
    if lstat(url.path, &st) != 0 { return errno == ENOENT ? .absent : .failed }
    if Int(st.st_size) > SpoolStore.maxFileBytes { return .tooLarge }
    do { return .data(try Data(contentsOf: url)) } catch {
      return Self.isProvenAbsent(url) ? .absent : .failed
    }
  }

  static let maxFileBytes =
    SpoolRecordCodec.maxRecordBytes + SpoolStoreConstants.nonceBytes + SpoolStoreConstants.tagBytes

  // MARK: Ack / sweep

  /// Deletes the given entries. Idempotent; malformed ids are ignored. The
  /// caller passes only ids its engine drained.
  @discardableResult
  func ack(_ ids: [String]) -> Int {
    var deleted = 0
    for id in ids where SpoolUlidGenerator.isValid(id) {
      if unlink(entry(id).path) == 0 { deleted += 1 }
    }
    return deleted
  }

  /// Removes `.tmp` files older than `tmpMaxAgeS` (a leftover of a killed
  /// write; a younger one may be another process's write in flight).
  @discardableResult
  func sweepTmp(now: Date = Date()) -> Int {
    state.lock.lock()
    defer { state.lock.unlock() }
    var swept = 0
    for name in listing(dir) ?? [] where Self.isTmpName(name) {
      let url = dir.appendingPathComponent(name)
      var st = stat()
      guard lstat(url.path, &st) == 0 else { continue }
      let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
      if now.timeIntervalSince(modified) >= Self.tmpMaxAgeS && unlink(url.path) == 0 { swept += 1 }
    }
    return swept
  }
}

enum SpoolIOError: Error { case listing }

enum SpoolStoreConstants {
  static let nonceBytes = 12
  static let tagBytes = 16
}
