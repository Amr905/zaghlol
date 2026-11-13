import Foundation

/// Why a user-part write failed.
enum GuardWriteErrorCode {
  /// The JSON did not pass the reader (or is over 64 KB); nothing was written.
  case configInvalid
  /// Keychain or file-system failure; the previous file is still in force.
  case ioError
}

/// A failed `writeGuardConfig`. Carries the code and, for `configInvalid`,
/// the reader's code and JSON path; never a value from the config.
struct GuardConfigWriteError: Error, CustomStringConvertible {
  let code: GuardWriteErrorCode
  let detail: GuardConfigError?

  init(_ code: GuardWriteErrorCode, detail: GuardConfigError? = nil) {
    self.code = code
    self.detail = detail
  }

  var description: String { "GuardConfigWriteError(\(code))" }
}

/// File operations of the store, a seam for fault injection in tests.
protocol GuardFileOps {
  /// Reads at most `max + 1` bytes of `url`. Returns nil only when the file
  /// is positively absent; any other failure throws (it proves nothing about
  /// the file).
  func readBounded(_ url: URL, max: Int) throws -> Data?
  func ensureDir(_ url: URL) throws
  /// Writes `data` to `url` (truncating), protects and fsyncs it.
  func writeAndSync(_ url: URL, data: Data) throws
  /// Atomically replaces `to` with `from`.
  func atomicReplace(from: URL, to: URL) throws
  /// Best-effort directory fsync after a rename; must not throw.
  func syncDir(_ url: URL)
  func delete(_ url: URL)
}

struct GuardFileOpsError: Error {}

/// POSIX / Foundation implementation.
struct DefaultGuardFileOps: GuardFileOps {
  func readBounded(_ url: URL, max: Int) throws -> Data? {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      // Positively absent only for "no such file"; a permission or
      // data-protection error proves nothing.
      let ns = error as NSError
      if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError { return nil }
      if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return nil }
      if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
        underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOENT)
      {
        return nil
      }
      throw error
    }
    defer { try? handle.close() }
    return try handle.read(upToCount: max + 1) ?? Data()
  }

  func ensureDir(_ url: URL) throws {
    // Backup-excluded like every Zaghlol directory (FR-SEC-05, T-165).
    try ZaghlolDirectories.ensureExcluded(url)
  }

  func writeAndSync(_ url: URL, data: Data) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    guard fm.createFile(atPath: url.path, contents: nil) else { throw GuardFileOpsError() }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.write(contentsOf: data)
    try handle.synchronize()
    // Shortcuts may run while the phone is locked after the first unlock.
    // Best effort: this is also the default class of a file in the container.
    try? fm.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path)
  }

  func atomicReplace(from: URL, to: URL) throws {
    // rename(2) atomically replaces an existing destination.
    if rename(from.path, to.path) != 0 { throw GuardFileOpsError() }
  }

  func syncDir(_ url: URL) {
    let fd = open(url.path, O_RDONLY)
    if fd < 0 { return }
    _ = fsync(fd)
    close(fd)
  }

  func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

/// The encrypted Guard user part on disk (T-038 design note section 5, iOS
/// path of platform-channels section 1.1): `<dir>/guard.user.enc`, AES-256-GCM
/// (`GuardUserCipher`), AAD `zaghlol.guard.v1|user`, written via `.tmp` +
/// fsync + atomic rename + best-effort directory fsync. Holds no state;
/// `GuardRuntime` serializes writes.
///
/// Never deletes the user file: an unreadable one is reported and kept (the
/// app rewrites it on every start); a left-over `.tmp` is ignored.
final class GuardUserConfigStore {
  static let dirName = "guard"
  static let fileName = "guard.user.enc"
  /// Binds the file to its role (platform-channels section 1.1).
  static let aad = Data("zaghlol.guard.v1|user".utf8)
  /// Largest file the writer can produce: a 64 KB part plus nonce and tag.
  static let maxFileBytes =
    GuardConfig.maxUserBytes + GuardUserCipherFormat.nonceBytes + GuardUserCipherFormat.tagBytes

  /// Outcome of `read`. No case prints content.
  enum Read {
    /// No user file: fresh install.
    case absent
    /// Decrypted plaintext.
    case plain(Data)
    /// Proven unusable: failed authentication, or a size the writer never produces.
    case unreadable
    /// I/O or Keychain error: proves nothing, retry on the next message.
    case transient
  }

  let dir: URL
  let file: URL
  private let tmp: URL
  private let cipher: GuardUserCipher
  private let ops: GuardFileOps

  init(dir: URL, cipher: GuardUserCipher, ops: GuardFileOps = DefaultGuardFileOps()) {
    self.dir = dir
    self.cipher = cipher
    self.ops = ops
    file = dir.appendingPathComponent(GuardUserConfigStore.fileName)
    tmp = dir.appendingPathComponent(GuardUserConfigStore.fileName + ".tmp")
  }

  /// The user-part directory under an App Group container
  /// (`Library/Application Support/guard`, backup-excluded with its parent).
  static func dir(inAppGroupContainer container: URL) -> URL {
    container.appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent(dirName, isDirectory: true)
  }

  func read() -> Read {
    let data: Data
    do {
      guard let d = try ops.readBounded(file, max: GuardUserConfigStore.maxFileBytes) else {
        return .absent
      }
      data = d
    } catch {
      return .transient
    }
    if data.count > GuardUserConfigStore.maxFileBytes { return .unreadable }
    do {
      return .plain(try cipher.decrypt(data, aad: GuardUserConfigStore.aad))
    } catch GuardCipherError.authentication {
      return .unreadable
    } catch {
      return .transient
    }
  }

  /// Encrypts and atomically replaces the user file. On any failure the
  /// previous file is untouched, the tmp is removed and
  /// `GuardConfigWriteError(.ioError)` is thrown. Does not validate `plain`:
  /// `GuardRuntime.writeUser` does, first.
  func write(_ plain: Data) throws {
    do {
      try ops.ensureDir(dir)
      let cipherText = try cipher.encrypt(plain, aad: GuardUserConfigStore.aad)
      try ops.writeAndSync(tmp, data: cipherText)
      try ops.atomicReplace(from: tmp, to: file)
    } catch {
      ops.delete(tmp)
      throw GuardConfigWriteError(.ioError)
    }
    ops.syncDir(dir)
  }
}
