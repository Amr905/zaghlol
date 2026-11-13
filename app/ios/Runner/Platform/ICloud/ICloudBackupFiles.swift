import CryptoKit
import Foundation

/// T-151: the file work behind `ICloudBackupHostApi` (task design note §2, §3,
/// §6). Works on any directory through `ICloudEnvironment`, so XCTest runs it
/// on a plain temp directory. Rules:
/// - only our backup names (final or `.partial`) are ever written, moved, read
///   or deleted; any other name is `invalidArgument`;
/// - nothing is ever overwritten: the partial is created with `O_EXCL`, the
///   final name by a move that refuses an existing file;
/// - the only file this code deletes on its own is the partial it created in
///   the same call, once it is proven wrong or cannot be finished;
/// - nothing here logs, and errors carry a code only.

/// Code-only failures. `code` is the wire code (platform-channels §5).
enum ICloudBackupError: Error, Equatable {
  case unavailable
  case invalidArgument
  case notFound
  case alreadyExists
  case uploadUnverified
  case tooLarge
  case timeout
  case io

  var code: String {
    switch self {
    case .unavailable: return "ICLOUD_UNAVAILABLE"
    case .invalidArgument: return "INVALID_ARGUMENT"
    case .notFound: return "NOT_FOUND"
    case .alreadyExists: return "ALREADY_EXISTS"
    case .uploadUnverified: return "UPLOAD_UNVERIFIED"
    case .tooLarge: return "TOO_LARGE"
    case .timeout: return "TIMEOUT"
    case .io: return "IO_ERROR"
    }
  }
}

/// Where the files live and how iCloud is asked about them.
protocol ICloudEnvironment {
  /// The ubiquity container root, or nil when iCloud is off / unavailable.
  /// Called off the main thread only.
  func containerURL() -> URL?

  /// A complete listing of our names directly in [dir], or a throw.
  func listItems(in dir: URL) throws -> [BackupMeta]

  /// Returns once the current version of [url] is on this phone.
  func ensureDownloaded(_ url: URL, timeout: TimeInterval) throws
}

enum ICloudBackupNames {
  /// Same cap as Dart's `maxBackupFileBytes` (T-150).
  static let maxBytes: Int64 = 1 << 30
  /// Listing cap: one more than Dart accepts, so Dart sees "too long".
  static let maxListed = 1001
  static let backupsPath = "Documents/Backups"
  static let downloadDirName = "zaghlol_backup_download"

  // `\A` / `\z`: ICU's `$` would also match before a trailing newline.
  private static let finalPattern = try! NSRegularExpression(
    pattern: #"\Azaghlol-backup-[0-9]{1,16}-[0-9]{1,16}\.zaghlol\.enc\z"#)
  private static let partialPattern = try! NSRegularExpression(
    pattern: #"\Azaghlol-backup-[0-9]{1,16}-[0-9]{1,16}\.zaghlol\.enc\.partial\z"#)

  private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    return re.firstMatch(in: s, options: [], range: range) != nil
  }

  static func isFinal(_ name: String) -> Bool { matches(finalPattern, name) }
  static func isPartial(_ name: String) -> Bool { matches(partialPattern, name) }
  static func isOurs(_ name: String) -> Bool { isFinal(name) || isPartial(name) }
}

final class ICloudBackupFiles {
  private let env: ICloudEnvironment
  private let tempRoot: URL
  private let downloadTimeout: TimeInterval
  private let fm = FileManager.default
  private static let chunk = 1 << 20

  init(env: ICloudEnvironment, tempRoot: URL, downloadTimeout: TimeInterval = 600) {
    self.env = env
    self.tempRoot = tempRoot
    self.downloadTimeout = downloadTimeout
  }

  func isAvailable() -> Bool { env.containerURL() != nil }

  private func backupsDir(create: Bool) throws -> URL {
    guard let root = env.containerURL() else { throw ICloudBackupError.unavailable }
    let dir = root.appendingPathComponent(ICloudBackupNames.backupsPath, isDirectory: true)
    if create {
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      } catch {
        throw ICloudBackupError.io
      }
    }
    return dir
  }

  /// The placeholder an evicted item may leave in a directory listing.
  private func stubURL(_ url: URL) -> URL {
    url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
  }

  // MARK: upload

  func upload(sourcePath: String, name: String) throws -> BackupMeta {
    guard ICloudBackupNames.isFinal(name), !sourcePath.isEmpty else {
      throw ICloudBackupError.invalidArgument
    }
    // iCloud off is reported before anything else is checked or touched.
    guard env.containerURL() != nil else { throw ICloudBackupError.unavailable }
    let source = URL(fileURLWithPath: sourcePath)
    let size = try regularFileSize(source)
    guard size >= 1 else { throw ICloudBackupError.invalidArgument }
    guard size <= ICloudBackupNames.maxBytes else { throw ICloudBackupError.tooLarge }

    let dir = try backupsDir(create: true)
    let final = dir.appendingPathComponent(name, isDirectory: false)
    let partial = dir.appendingPathComponent(name + ".partial", isDirectory: false)
    if fm.fileExists(atPath: final.path) || fm.fileExists(atPath: stubURL(final).path) {
      throw ICloudBackupError.alreadyExists
    }

    // 1. Copy into a partial this call creates (O_EXCL), hashing the source.
    var created = false
    let sourceMd5: String
    do {
      sourceMd5 = try coordinateWrite(partial, options: []) { url in
        try self.copyExclusive(from: source, to: url, expected: size, created: &created)
      }
    } catch {
      if created { removeOwnPartial(partial) }
      throw error
    }

    // 2. Read the partial back; a mismatch proves it wrong.
    let readBack: (Int64, String)
    do {
      readBack = try coordinateRead(partial) { try Self.md5(of: $0) }
    } catch {
      removeOwnPartial(partial)
      throw error
    }
    guard readBack.0 == size, readBack.1 == sourceMd5 else {
      removeOwnPartial(partial)
      throw ICloudBackupError.uploadUnverified
    }

    // 3. Move to the final name; never replaces an existing file.
    do {
      try coordinateMove(from: partial, to: final)
    } catch {
      removeOwnPartial(partial)
      throw error
    }

    // 4. Read the final back for Dart's comparison with its local file.
    let finalHash = try coordinateRead(final) { try Self.md5(of: $0) }
    guard finalHash.0 == size, finalHash.1 == sourceMd5 else {
      throw ICloudBackupError.uploadUnverified
    }
    let attrs = try? fm.attributesOfItem(atPath: final.path)
    let createdAt = (attrs?[.creationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) }
    return BackupMeta(
      name: name, sizeBytes: size, createdAtMs: createdAt, isUploaded: false,
      isDownloaded: true, quotaExceeded: false, uploadFailed: false, md5: finalHash.1)
  }

  private func regularFileSize(_ url: URL) throws -> Int64 {
    let attrs: [FileAttributeKey: Any]
    do {
      attrs = try fm.attributesOfItem(atPath: url.path)
    } catch {
      throw ICloudBackupError.invalidArgument
    }
    guard (attrs[.type] as? FileAttributeType) == .typeRegular,
      let n = (attrs[.size] as? NSNumber)?.int64Value
    else { throw ICloudBackupError.invalidArgument }
    return n
  }

  private func copyExclusive(
    from source: URL, to dest: URL, expected: Int64, created: inout Bool
  ) throws -> String {
    let fd = open(dest.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    if fd < 0 {
      throw errno == EEXIST ? ICloudBackupError.alreadyExists : ICloudBackupError.io
    }
    created = true
    let out = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    let input: FileHandle
    do {
      input = try FileHandle(forReadingFrom: source)
    } catch {
      try? out.close()
      throw ICloudBackupError.io
    }
    defer { try? input.close() }
    var hasher = Insecure.MD5()
    var total: Int64 = 0
    do {
      while true {
        guard let data = try input.read(upToCount: Self.chunk), !data.isEmpty else { break }
        total += Int64(data.count)
        if total > expected { throw ICloudBackupError.uploadUnverified }
        hasher.update(data: data)
        try out.write(contentsOf: data)
      }
      try out.synchronize()
      try out.close()
    } catch let e as ICloudBackupError {
      try? out.close()
      throw e
    } catch {
      try? out.close()
      throw ICloudBackupError.io
    }
    guard total == expected else { throw ICloudBackupError.uploadUnverified }
    return Self.hex(hasher.finalize())
  }

  /// Deletes the partial this call created. Best effort: a leftover is swept
  /// by a later prune (Dart, ≥ 24 h older than a verified upload).
  private func removeOwnPartial(_ partial: URL) {
    try? coordinateWrite(partial, options: .forDeleting) { url in
      try self.fm.removeItem(at: url)
    }
  }

  static func md5(of url: URL) throws -> (Int64, String) {
    let input: FileHandle
    do {
      input = try FileHandle(forReadingFrom: url)
    } catch {
      throw ICloudBackupError.io
    }
    defer { try? input.close() }
    var hasher = Insecure.MD5()
    var total: Int64 = 0
    do {
      while true {
        guard let data = try input.read(upToCount: chunk), !data.isEmpty else { break }
        total += Int64(data.count)
        if total > ICloudBackupNames.maxBytes { throw ICloudBackupError.tooLarge }
        hasher.update(data: data)
      }
    } catch let e as ICloudBackupError {
      throw e
    } catch {
      throw ICloudBackupError.io
    }
    return (total, hex(hasher.finalize()))
  }

  private static func hex(_ digest: Insecure.MD5Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: list

  func list() throws -> [BackupMeta] {
    let dir = try backupsDir(create: false)
    let items = try env.listItems(in: dir)
    let ours = items.filter { ICloudBackupNames.isOurs($0.name) }
    return Array(ours.prefix(ICloudBackupNames.maxListed))
  }

  // MARK: download

  func download(name: String) throws -> String {
    guard ICloudBackupNames.isFinal(name) else { throw ICloudBackupError.invalidArgument }
    let dir = try backupsDir(create: false)
    let url = dir.appendingPathComponent(name, isDirectory: false)
    try env.ensureDownloaded(url, timeout: downloadTimeout)
    let size = try regularFileSize(url)
    guard size >= 1 else { throw ICloudBackupError.invalidArgument }
    guard size <= ICloudBackupNames.maxBytes else { throw ICloudBackupError.tooLarge }

    let outDir = tempRoot.appendingPathComponent(ICloudBackupNames.downloadDirName, isDirectory: true)
    do {
      // Only our own earlier download copies (ciphertext) live here.
      if fm.fileExists(atPath: outDir.path) { try fm.removeItem(at: outDir) }
      try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
    } catch {
      throw ICloudBackupError.io
    }
    let dest = outDir.appendingPathComponent(UUID().uuidString + ".zaghlol.enc")
    try coordinateRead(url) { src in
      do {
        try self.fm.copyItem(at: src, to: dest)
      } catch {
        throw ICloudBackupError.io
      }
    }
    return dest.path
  }

  // MARK: delete

  func delete(name: String) throws {
    guard ICloudBackupNames.isOurs(name) else { throw ICloudBackupError.invalidArgument }
    let dir = try backupsDir(create: false)
    let url = dir.appendingPathComponent(name, isDirectory: false)
    let stub = stubURL(url)
    let target: URL
    if fm.fileExists(atPath: url.path) {
      target = url
    } else if fm.fileExists(atPath: stub.path) {
      target = stub
    } else {
      throw ICloudBackupError.notFound
    }
    try coordinateWrite(target, options: .forDeleting) { u in
      do {
        try self.fm.removeItem(at: u)
      } catch let e as CocoaError where e.code == .fileNoSuchFile {
        throw ICloudBackupError.notFound
      } catch {
        throw ICloudBackupError.io
      }
    }
  }

  // MARK: coordination

  private func coordinateWrite<T>(
    _ url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> T
  ) throws -> T {
    var coordError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: options, error: &coordError
    ) { u in
      result = Result { try body(u) }
    }
    return try finish(result, coordError)
  }

  private func coordinateRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
    var coordError: NSError?
    var result: Result<T, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(
      readingItemAt: url, options: [.withoutChanges], error: &coordError
    ) { u in
      result = Result { try body(u) }
    }
    return try finish(result, coordError)
  }

  private func coordinateMove(from src: URL, to dst: URL) throws {
    var coordError: NSError?
    var result: Result<Void, Error>?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(
      writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing,
      error: &coordError
    ) { s, d in
      result = Result {
        coordinator.item(at: s, willMoveTo: d)
        do {
          // moveItem never replaces: an existing destination is an error.
          try self.fm.moveItem(at: s, to: d)
        } catch let e as CocoaError where e.code == .fileWriteFileExists {
          throw ICloudBackupError.alreadyExists
        } catch {
          throw ICloudBackupError.io
        }
        coordinator.item(at: s, didMoveTo: d)
      }
    }
    try finish(result, coordError)
  }

  private func finish<T>(_ result: Result<T, Error>?, _ coordError: NSError?) throws -> T {
    guard let result = result else {
      _ = coordError
      throw ICloudBackupError.io
    }
    switch result {
    case .success(let v): return v
    case .failure(let e as ICloudBackupError): throw e
    case .failure: throw ICloudBackupError.io
    }
  }
}
