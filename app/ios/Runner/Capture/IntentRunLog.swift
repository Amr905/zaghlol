import Foundation

/// Which App Intent ran (per-intent last-run time, T-064's setup checker).
enum CaptureIntentKind: CaseIterable {
  case message
  case wallet
}

/// T-063: the last time each App Intent ran (wall-clock epoch ms), whatever
/// the Guard decided, so the setup checker (T-064, FR-ING-I-07) can tell an
/// automation that never fires from one that only sees non-bank messages.
///
/// Times only, never content. Encrypted with the spool cipher like the
/// capture status: `<App Group>/Library/Application Support/capture/intent_runs.bin`,
/// AAD `zaghlol.capture.v1|intent_runs`, plaintext `u8 v=1 | i64 message | i64 wallet`
/// (big-endian, -1 = never). Written via `.tmp` + rename. A failure (before
/// the first unlock, I/O) skips the record: it is diagnostic, and the next
/// run writes again.
final class IntentRunLog {
  static let aad = Data("zaghlol.capture.v1|intent_runs".utf8)
  static let version: UInt8 = 1
  static let plainBytes = 17

  struct Runs: Equatable {
    var messageAtMs: Int64?
    var walletAtMs: Int64?
  }

  let file: URL
  private let cipher: SpoolCipher
  private let excludeDir: (URL) throws -> Void
  private let lock = NSLock()

  init(
    file: URL, cipher: SpoolCipher,
    excludeDir: @escaping (URL) throws -> Void = ZaghlolDirectories.ensureExcluded
  ) {
    self.file = file
    self.cipher = cipher
    self.excludeDir = excludeDir
  }

  static func file(in container: URL) -> URL {
    container.appendingPathComponent("Library/Application Support/capture/intent_runs.bin")
  }

  /// The recorded times; empty when there is no file or it can't be read now.
  func read() -> Runs {
    lock.lock()
    defer { lock.unlock() }
    return readLocked() ?? Runs()
  }

  /// Records `kind` at `atMs`. Never throws.
  func record(_ kind: CaptureIntentKind, atMs: Int64) {
    lock.lock()
    defer { lock.unlock() }
    var runs = readLocked() ?? Runs()
    switch kind {
    case .message: runs.messageAtMs = atMs
    case .wallet: runs.walletAtMs = atMs
    }
    var plain = Data([Self.version])
    for v in [runs.messageAtMs ?? -1, runs.walletAtMs ?? -1] {
      withUnsafeBytes(of: UInt64(bitPattern: v).bigEndian) { plain.append(contentsOf: $0) }
    }
    let dir = file.deletingLastPathComponent()
    let tmp = dir.appendingPathComponent(file.lastPathComponent + ".tmp")
    do {
      try excludeDir(dir)
      let sealed = try cipher.encrypt(plain, aad: Self.aad)
      try sealed.write(to: tmp, options: [.completeFileProtectionUntilFirstUserAuthentication])
      if rename(tmp.path, file.path) != 0 { unlink(tmp.path) }
    } catch {
      unlink(tmp.path)
    }
  }

  private func readLocked() -> Runs? {
    guard let data = try? Data(contentsOf: file),
      let plain = try? cipher.decrypt(data, aad: Self.aad),
      plain.count == Self.plainBytes, plain.first == Self.version
    else { return nil }
    let bytes = [UInt8](plain)
    func i64(_ at: Int) -> Int64? {
      let v = Int64(bitPattern: bytes[at..<at + 8].reduce(0) { ($0 << 8) | UInt64($1) })
      return v < 0 ? nil : v
    }
    return Runs(messageAtMs: i64(1), walletAtMs: i64(9))
  }
}
