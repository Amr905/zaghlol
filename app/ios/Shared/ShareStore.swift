import Foundation

/// T-065: the encrypted share store (platform-channels.md 2.1 and 3). The Share
/// Extension writes one share (text, image or PDF) per entry; the app reads it
/// on its next foreground, shows the confirmation or OCR flow and discards it.
///
/// Everything here is financial data: nothing logs, errors carry no text, the
/// body and the metadata are AES-GCM encrypted with the spool key and are never
/// on disk in plaintext, and every failed or partial write is removed.
///
/// Directory `<App Group container>/spool/files/` (never the container root):
/// - `<id>.bin`  = AES-GCM(payload), AAD `zaghlol.spool.v1|file|<id>.bin`. This is
///   the layout `SpoolFileImageSource` (OCR host, T-160) reads, so a shared
///   image can be recognized in place.
/// - `<id>.meta` = AES-GCM(JSON metadata), AAD `zaghlol.share.v1|meta|<id>`.
///   The meta file is written last and is the commit point: a share without
///   it does not exist.
/// - `rejection.bin` = AES-GCM(1 byte), AAD `zaghlol.share.v1|rejection`: why the
///   last share was refused, for the app to show once.

enum ShareFileKind: Int {
  case text = 0
  case image = 1
  case pdf = 2

  /// Pigeon `ShareKind` order: text, image, pdf (csv is Android only).
  var contentTypeName: String {
    switch self {
    case .text: return "text/plain"
    case .image: return "image"
    case .pdf: return "application/pdf"
    }
  }
}

enum ShareRejection: UInt8 {
  case tooLarge = 0
  case unsupportedType = 1
  case unreadable = 2
  case empty = 3
}

struct ShareMeta: Equatable {
  let id: String
  let kind: ShareFileKind
  let mimeType: String
  let sizeBytes: Int64
  let receivedAtMs: Int64
}

/// Code only: no path, no text, no byte counts.
enum ShareStoreError: Error, Equatable {
  /// A limit (pending count or total size) refused the share.
  case tooLarge
  /// The cipher or Keychain could not be used now; nothing was deleted.
  case unavailable
  /// A file step failed; every file of the share was removed.
  case io
  /// Provably not a share this code wrote (tag failure, bad meta). Deleted.
  case notAuthentic
  case notFound
}

private struct ShareMetaJson: Codable {
  let v: Int
  let k: Int
  let m: String
  let s: Int64
  let t: Int64
}

final class ShareStore {
  static let bodySuffix = ".bin"
  static let metaSuffix = ".meta"
  static let tmpSuffix = ".tmp"
  static let rejectionName = "rejection.bin"
  static let maxPending = 10
  static let maxTotalBytes: Int64 = 100 * 1024 * 1024
  static let staleAgeMs: Int64 = 24 * 60 * 60 * 1000
  static let tmpMaxAgeS: TimeInterval = 600

  let dir: URL
  private let cipher: SpoolCipher
  private let files: SpoolFileOps
  private let ids: SpoolUlidGenerator
  private let wallClock: () -> Int64
  private let excludeDir: (URL) throws -> Void
  private let fm = FileManager.default

  init(
    dir: URL, cipher: SpoolCipher, files: SpoolFileOps = DefaultSpoolFileOps(),
    ids: SpoolUlidGenerator = SpoolUlidGenerator(),
    wallClock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    excludeDir: @escaping (URL) throws -> Void = { try ZaghlolDirectories.ensureExcluded($0) }
  ) {
    self.dir = dir
    self.cipher = cipher
    self.files = files
    self.ids = ids
    self.wallClock = wallClock
    self.excludeDir = excludeDir
  }

  // MARK: Names and AAD

  static func bodyAad(_ id: String) -> Data { Data("zaghlol.spool.v1|file|\(id).bin".utf8) }
  static func metaAad(_ id: String) -> Data { Data("zaghlol.share.v1|meta|\(id)".utf8) }
  static let rejectionAad = Data("zaghlol.share.v1|rejection".utf8)

  /// ULID: 26 Crockford base32 characters. Anything else is never a path part.
  static func isValidId(_ id: String) -> Bool {
    id.utf8.count == 26 && id.utf8.allSatisfy { c in
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A && c != 0x49 && c != 0x4C && c != 0x4F && c != 0x55)
    }
  }

  private func body(_ id: String) -> URL { dir.appendingPathComponent(id + Self.bodySuffix) }
  private func meta(_ id: String) -> URL { dir.appendingPathComponent(id + Self.metaSuffix) }
  private func tmp(_ url: URL) -> URL { url.appendingPathExtension("tmp") }
  private var rejectionFile: URL { dir.appendingPathComponent(Self.rejectionName) }

  // MARK: Write

  /// Encrypts and stores one share. `payload` is zeroed before this returns.
  /// On any failure nothing of the share stays on disk.
  func add(kind: ShareFileKind, mimeType: String, payload: inout Data) throws -> ShareMeta {
    defer { payload.resetBytes(in: 0..<payload.count) }
    do { try excludeDir(dir) } catch { throw ShareStoreError.io }
    try admit(newBytes: Int64(payload.count))

    let id = ids.next()
    let info = ShareMeta(
      id: id, kind: kind, mimeType: mimeType, sizeBytes: Int64(payload.count),
      receivedAtMs: wallClock())
    guard
      let metaPlain = try? JSONEncoder().encode(
        ShareMetaJson(
          v: 1, k: kind.rawValue, m: mimeType, s: info.sizeBytes, t: info.receivedAtMs))
    else { throw ShareStoreError.io }

    let sealedBody = try seal(payload, aad: Self.bodyAad(id))
    let sealedMeta = try seal(metaPlain, aad: Self.metaAad(id))
    do {
      try put(sealedBody, to: body(id))  // the body first,
      try put(sealedMeta, to: meta(id))  // then the commit point
      files.syncDir(dir)
    } catch {
      removeAll(id)
      throw ShareStoreError.io
    }
    return info
  }

  private func seal(_ plain: Data, aad: Data) throws -> Data {
    do { return try cipher.encrypt(plain, aad: aad) } catch { throw ShareStoreError.unavailable }
  }

  /// `.tmp` + fsync + atomic rename: the final name is complete or absent.
  private func put(_ sealed: Data, to url: URL) throws {
    let t = tmp(url)
    try files.create(t, contents: sealed)
    do { try files.move(t, url) } catch {
      try? fm.removeItem(at: t)
      throw error
    }
  }

  private func admit(newBytes: Int64) throws {
    sweepTmp()
    var count = 0
    var total: Int64 = 0
    for name in names() where name.hasSuffix(Self.metaSuffix) { count += 1 }
    for name in names() where name.hasSuffix(Self.bodySuffix) && name != Self.rejectionName {
      total += fileSize(dir.appendingPathComponent(name))
    }
    if count >= Self.maxPending || total + newBytes > Self.maxTotalBytes {
      throw ShareStoreError.tooLarge
    }
  }

  // MARK: Read

  /// Pending shares, oldest first. Removes stale (older than 24 h) shares,
  /// shares whose body is gone (already consumed by OCR) and shares that are
  /// provably not authentic. A cipher failure skips the entry and deletes nothing.
  func list() -> [ShareMeta] {
    sweepTmp()
    var out: [ShareMeta] = []
    let now = wallClock()
    for name in names().sorted() where name.hasSuffix(Self.metaSuffix) {
      let id = String(name.dropLast(Self.metaSuffix.count))
      guard Self.isValidId(id) else { continue }
      switch readMeta(id) {
      case .success(let m):
        if now - m.receivedAtMs > Self.staleAgeMs || !fm.fileExists(atPath: body(id).path) {
          removeAll(id)
        } else {
          out.append(m)
        }
      case .failure(.notAuthentic): removeAll(id)
      case .failure: continue
      }
    }
    // A body with no meta older than the tmp age is an interrupted write.
    for name in names() where name.hasSuffix(Self.bodySuffix) && name != Self.rejectionName {
      let id = String(name.dropLast(Self.bodySuffix.count))
      if Self.isValidId(id), !fm.fileExists(atPath: meta(id).path),
        age(of: dir.appendingPathComponent(name)) > Self.tmpMaxAgeS
      {
        try? fm.removeItem(at: body(id))
      }
    }
    return out.sorted { ($0.receivedAtMs, $0.id) < ($1.receivedAtMs, $1.id) }
  }

  /// Decrypts a share in memory. A failed tag deletes the share (proof);
  /// every other failure keeps it for a retry.
  func read(_ id: String) throws -> (meta: ShareMeta, payload: Data) {
    guard Self.isValidId(id) else { throw ShareStoreError.notFound }
    let info: ShareMeta
    switch readMeta(id) {
    case .success(let m): info = m
    case .failure(.notAuthentic):
      removeAll(id)
      throw ShareStoreError.notAuthentic
    case .failure(let e): throw e
    }
    guard let sealed = readBounded(body(id)) else { throw ShareStoreError.notFound }
    do {
      return (info, try cipher.decrypt(sealed, aad: Self.bodyAad(id)))
    } catch SpoolCipherError.notAuthentic {
      removeAll(id)
      throw ShareStoreError.notAuthentic
    } catch {
      throw ShareStoreError.unavailable
    }
  }

  private func readMeta(_ id: String) -> Result<ShareMeta, ShareStoreError> {
    guard let sealed = readBounded(meta(id), limit: 4_096) else { return .failure(.notFound) }
    let plain: Data
    do { plain = try cipher.decrypt(sealed, aad: Self.metaAad(id)) } catch SpoolCipherError.notAuthentic {
      return .failure(.notAuthentic)
    } catch { return .failure(.unavailable) }
    guard let j = try? JSONDecoder().decode(ShareMetaJson.self, from: plain), j.v == 1,
      let kind = ShareFileKind(rawValue: j.k), j.s >= 0, j.m.utf8.count <= 128
    else { return .failure(.notAuthentic) }
    return .success(ShareMeta(id: id, kind: kind, mimeType: j.m, sizeBytes: j.s, receivedAtMs: j.t))
  }

  /// Deletes every file of the share. Idempotent.
  func discard(_ id: String) {
    guard Self.isValidId(id) else { return }
    removeAll(id)
  }

  // MARK: Rejection slot

  func setRejection(_ reason: ShareRejection) {
    do {
      try excludeDir(dir)
      let sealed = try cipher.encrypt(Data([reason.rawValue]), aad: Self.rejectionAad)
      try put(sealed, to: rejectionFile)
    } catch {
      try? fm.removeItem(at: tmp(rejectionFile))
    }
  }

  /// The last refusal, once.
  func takeRejection() -> ShareRejection? {
    guard let sealed = readBounded(rejectionFile, limit: 256) else { return nil }
    do {
      let plain = try cipher.decrypt(sealed, aad: Self.rejectionAad)
      try? fm.removeItem(at: rejectionFile)
      return plain.count == 1 ? ShareRejection(rawValue: plain[0]) : nil
    } catch SpoolCipherError.notAuthentic {
      try? fm.removeItem(at: rejectionFile)
      return nil
    } catch { return nil }
  }

  // MARK: Helpers

  private func removeAll(_ id: String) {
    for url in [body(id), meta(id), tmp(body(id)), tmp(meta(id))] { try? fm.removeItem(at: url) }
  }

  private func names() -> [String] { (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] }

  private func fileSize(_ url: URL) -> Int64 {
    var st = stat()
    return lstat(url.path, &st) == 0 ? Int64(st.st_size) : 0
  }

  private func age(of url: URL) -> TimeInterval {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return 0 }
    return Date().timeIntervalSince1970 - TimeInterval(st.st_mtimespec.tv_sec)
  }

  private func readBounded(_ url: URL, limit: Int = ShareLimits.maxFileBytes + 64) -> Data? {
    guard fileSize(url) <= limit, let d = try? Data(contentsOf: url) else { return nil }
    return d
  }

  /// Removes `.tmp` files older than the tmp age (a younger one may be another
  /// process's write in flight).
  @discardableResult
  func sweepTmp() -> Int {
    var n = 0
    for name in names() where name.hasSuffix(Self.tmpSuffix) {
      let url = dir.appendingPathComponent(name)
      if age(of: url) > Self.tmpMaxAgeS, (try? fm.removeItem(at: url)) != nil { n += 1 }
    }
    return n
  }
}
