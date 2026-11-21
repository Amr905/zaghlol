import Foundation

/// T-118: what the home-screen widget shows. Already-formatted,
/// redaction-aware strings from Dart: when amounts are hidden, or the app is
/// locked, the amount is not in here at all, only the mask. Nothing is parsed
/// or computed natively.
struct WidgetView: Equatable {
  static let stateOk = 0
  static let stateNoBudget = 1
  static let stateNoData = 2
  static let maxTextChars = 120

  var state: Int
  var primaryText: String
  var secondaryText: String
  var currency: String
  var updatedAtMs: Int64
  var daysToPayday: Int?
  /// Finished line two for day 0 (the day of `updatedAtMs`), day 1, ... (FU-206b).
  /// Empty on a v1 file.
  var secondaryByDay: [String] = []

  /// Line two for `now`: the entry for the number of local midnights since
  /// `updatedAtMs` (FU-206b), so days-to-payday rolls without the app. Past the
  /// last entry it is empty (the app must republish a new cycle). Without a
  /// list (v1) the stored line is kept.
  func secondary(at now: Date, calendar: Calendar = .current) -> String {
    if secondaryByDay.isEmpty { return secondaryText }
    let then = Date(timeIntervalSince1970: TimeInterval(updatedAtMs) / 1000)
    let elapsed =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now)
      ).day ?? 0
    let i = max(elapsed, 0)
    return i < secondaryByDay.count ? secondaryByDay[i] : ""
  }

  /// The local midnights (after `now`) at which line two changes, for a timeline.
  func rollDates(after now: Date, calendar: Calendar = .current) -> [Date] {
    if secondaryByDay.isEmpty { return [] }
    let then = Date(timeIntervalSince1970: TimeInterval(updatedAtMs) / 1000)
    let start = calendar.startOfDay(for: then)
    return (1...secondaryByDay.count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
      .filter { $0 > now }
  }
}

struct WidgetSnapshotFormatError: Error {}

/// `<App Group>/Library/Application Support/widget/snapshot.bin`: AES-GCM with
/// the spool key (shared Keychain access group, T-062), AAD
/// `zaghlol.widget.v1|snapshot`, a small binary record v1 (big-endian). The
/// directory is excluded from backup (`ZaghlolDirectories.ensureExcluded`,
/// T-165) before every write; the file is replaced atomically. The app writes,
/// the widget extension reads.
///
/// A file that can't be read (lost key, tampering, corruption, Keychain not
/// available yet) reads as `nil`, which the widget shows as the app name; it is
/// never deleted on a read and nothing is logged.
final class WidgetSnapshotStore {
  static let version: UInt8 = 2
  static let maxFileBytes = 16384
  static let maxDays = 62
  static let aad = Data("zaghlol.widget.v1|snapshot".utf8)

  private let file: URL
  private let cipher: SpoolCipher
  private let excludeDir: (URL) throws -> Void

  init(
    file: URL, cipher: SpoolCipher,
    excludeDir: @escaping (URL) throws -> Void = ZaghlolDirectories.ensureExcluded
  ) {
    self.file = file
    self.cipher = cipher
    self.excludeDir = excludeDir
  }

  /// The production store over the App Group container, or `nil` without the
  /// App Group entitlement (a build defect on a device).
  static func production(
    appGroupIdentifier: String? = ZaghlolDirectories.appGroupIdentifier,
    fileManager: FileManager = .default
  ) -> WidgetSnapshotStore? {
    guard let id = appGroupIdentifier,
      let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: id)
    else { return nil }
    return WidgetSnapshotStore(
      file: container.appendingPathComponent("Library/Application Support/widget/snapshot.bin"),
      cipher: KeychainSpoolCipher())
  }

  func write(_ view: WidgetView) throws {
    try excludeDir(file.deletingLastPathComponent())
    let sealed = try cipher.encrypt(Self.encode(view), aad: Self.aad)
    try sealed.write(
      to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func readOrNil() -> WidgetView? {
    guard let bytes = try? Data(contentsOf: file), bytes.count <= Self.maxFileBytes else {
      return nil
    }
    guard let plain = try? cipher.decrypt(bytes, aad: Self.aad) else { return nil }
    return try? Self.decode(plain)
  }

  /// Idempotent.
  func clear() throws {
    do {
      try FileManager.default.removeItem(at: file)
    } catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileNoSuchFileError {
      // already gone
    }
  }

  // MARK: Record

  /// `u8 v=2 | u8 state | str primary | str secondary | str currency |
  ///  i64 updatedAtMs | i32 days (-1 = none) | u16 n | n x str` (v2; v1 ends
  ///  after days); `str` = u16 length + UTF-8.
  static func encode(_ v: WidgetView) -> Data {
    var out = Data([version, UInt8(truncatingIfNeeded: v.state)])
    func put<T: FixedWidthInteger>(_ x: T) { withUnsafeBytes(of: x.bigEndian) { out.append(contentsOf: $0) } }
    func str(_ s: String, max: Int) {
      let bytes = Array(String(s.prefix(max)).utf8)
      put(UInt16(bytes.count))
      out.append(contentsOf: bytes)
    }
    str(v.primaryText, max: WidgetView.maxTextChars)
    str(v.secondaryText, max: WidgetView.maxTextChars)
    str(v.currency, max: 8)
    put(v.updatedAtMs)
    put(Int32(v.daysToPayday ?? -1))
    let byDay = Array(v.secondaryByDay.prefix(maxDays))
    put(UInt16(byDay.count))
    for line in byDay { str(line, max: WidgetView.maxTextChars) }
    return out
  }

  static func decode(_ data: Data) throws -> WidgetView {
    let b = [UInt8](data)
    var pos = 0
    func need(_ n: Int) throws { if pos + n > b.count { throw WidgetSnapshotFormatError() } }
    func u8() throws -> UInt8 { try need(1); defer { pos += 1 }; return b[pos] }
    func u16() throws -> Int {
      try need(2); defer { pos += 2 }
      return Int(b[pos]) << 8 | Int(b[pos + 1])
    }
    func i64() throws -> Int64 {
      try need(8); defer { pos += 8 }
      return Int64(bitPattern: b[pos..<pos + 8].reduce(0) { ($0 << 8) | UInt64($1) })
    }
    func i32() throws -> Int32 {
      try need(4); defer { pos += 4 }
      return Int32(bitPattern: b[pos..<pos + 4].reduce(0) { ($0 << 8) | UInt32($1) })
    }
    func str() throws -> String {
      let n = try u16()
      try need(n); defer { pos += n }
      guard let s = String(bytes: b[pos..<pos + n], encoding: .utf8) else {
        throw WidgetSnapshotFormatError()
      }
      return s
    }
    let fileVersion = try u8()
    guard fileVersion == 1 || fileVersion == version else { throw WidgetSnapshotFormatError() }
    let state = Int(try u8())
    guard state <= WidgetView.stateNoData else { throw WidgetSnapshotFormatError() }
    let primary = try str()
    let secondary = try str()
    let currency = try str()
    let updated = try i64()
    let days = try i32()
    var byDay: [String] = []
    if fileVersion >= 2 {
      let n = try u16()
      guard n <= maxDays else { throw WidgetSnapshotFormatError() }
      for _ in 0..<n { byDay.append(try str()) }
    }
    guard pos == b.count else { throw WidgetSnapshotFormatError() }
    return WidgetView(
      state: state, primaryText: primary, secondaryText: secondary, currency: currency,
      updatedAtMs: updated, daysToPayday: days < 0 ? nil : Int(days), secondaryByDay: byDay)
  }
}
