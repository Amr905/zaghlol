import Foundation
import Security

/// ULIDs for spool entry names (Crockford base32, 26 chars: 48-bit ms time +
/// 80 random bits). Same format as the Android spool, so the Dart drain is
/// shared. Monotonic within the process; entries written in the same
/// millisecond still sort in write order.
final class SpoolUlidGenerator {
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  private let clock: () -> Int64
  private let lock = NSLock()
  private var lastMs: Int64 = -1
  private var lastRandom = [UInt8](repeating: 0, count: 10)

  init(clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
    self.clock = clock
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    let now = clock()
    if now <= lastMs {
      increment()
    } else {
      lastMs = now
      var bytes = [UInt8](repeating: 0, count: 10)
      if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
      }
      bytes[0] &= 0x7F  // headroom for increments
      lastRandom = bytes
    }
    return Self.encode(ms: lastMs, random: lastRandom)
  }

  private func increment() {
    for i in lastRandom.indices.reversed() {
      if lastRandom[i] == 0xFF {
        lastRandom[i] = 0
      } else {
        lastRandom[i] += 1
        return
      }
    }
  }

  static func isValid(_ id: String) -> Bool {
    let chars = Array(id.utf8)
    guard chars.count == 26 else { return false }
    let allowed = Set(alphabet.map { $0.asciiValue! })
    return chars.allSatisfy { allowed.contains($0) }
  }

  /// The millisecond time of a valid ULID (its first 10 characters).
  static func timeMs(_ id: String) -> Int64? {
    guard isValid(id) else { return nil }
    var t: Int64 = 0
    for ch in id.prefix(10) { t = (t << 5) | Int64(alphabet.firstIndex(of: ch)!) }
    return t
  }

  static func encode(ms: Int64, random: [UInt8]) -> String {
    var out = [Character](repeating: "0", count: 26)
    var t = ms
    for i in stride(from: 9, through: 0, by: -1) {
      out[i] = alphabet[Int(t & 31)]
      t >>= 5
    }
    var acc: UInt64 = 0
    var bits = 0
    var pos = 10
    for b in random {
      acc = (acc << 8) | UInt64(b)
      bits += 8
      while bits >= 5 {
        bits -= 5
        out[pos] = alphabet[Int((acc >> UInt64(bits)) & 31)]
        pos += 1
      }
    }
    return String(out)
  }
}
