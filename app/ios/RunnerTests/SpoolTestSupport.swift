import CryptoKit
import Foundation

@testable import Runner

/// Synthetic key and bodies only; never real messages.
let spoolCanary = "ZG_CANARY_7731"

final class TestCipher: SpoolCipher {
  let key: SymmetricKey
  var createdAtMs: Int64?
  var failWith: SpoolCipherError?
  init(seed: UInt8 = 7, createdAtMs: Int64? = nil) {
    key = SymmetricKey(data: Data((0..<32).map { UInt8(truncatingIfNeeded: Int($0) &* 31 &+ Int(seed)) }))
    self.createdAtMs = createdAtMs
  }
  func keyCreatedAtMs() -> Int64? { createdAtMs }
  func encrypt(_ plain: Data, aad: Data) throws -> Data {
    if let e = failWith { throw e }
    return try AES.GCM.seal(plain, using: key, authenticating: aad).combined!
  }
  func decrypt(_ data: Data, aad: Data) throws -> Data {
    if let e = failWith { throw e }
    if data.count < 28 { throw SpoolCipherError.notAuthentic }
    do { return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key, authenticating: aad) } catch {
      throw SpoolCipherError.notAuthentic
    }
  }
}

func makeTempDir() throws -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("t062-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

func sampleRecord(
  _ body: String = "synthetic \(spoolCanary) EGP 12.50", channel: String = "shortcut_message",
  source: String = "SYNTH-BANK"
) -> SpoolRecord {
  SpoolRecord(channel: channel, source: source, body: body, receivedAtMs: 1_700_000_000_000)
}

func isExcludedFromBackup(_ url: URL) throws -> Bool {
  let fresh = URL(fileURLWithPath: url.path, isDirectory: true)
  return try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
}

/// A file-ops fake that fails one step.
final class FaultyOps: SpoolFileOps {
  enum Step { case create, move }
  var failAt: Step?
  var moves = 0
  struct Boom: Error {}
  private let real = DefaultSpoolFileOps()
  func create(_ url: URL, contents: Data) throws {
    if failAt == .create { throw Boom() }
    try real.create(url, contents: contents)
  }
  func move(_ from: URL, _ to: URL) throws {
    moves += 1
    if failAt == .move { throw Boom() }
    try real.move(from, to)
  }
  func syncDir(_ dir: URL) { real.syncDir(dir) }
}
