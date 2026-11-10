import Foundation

/// T-015: the process-wide bootstrap lease (design note §3). Serialises the key
/// bootstrap and database creation/wipe between every Flutter engine in the
/// process. A lease expires `ttlNanos` after it was taken, so a dead engine
/// can't block the others. No logging in this folder (FU-050).
final class BootstrapLeaseManager {
  static let process = BootstrapLeaseManager()

  private let condition = NSCondition()
  private let ttlNanos: UInt64
  private let clock: () -> UInt64
  private var current: Int64 = 0
  private var expiresAt: UInt64 = 0
  private var nextId: Int64 = 1

  init(
    ttlNanos: UInt64 = 30 * 1_000_000_000,
    clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) {
    self.ttlNanos = ttlNanos
    self.clock = clock
  }

  /// Takes the lease, waiting at most `timeoutMs`. Returns nil on timeout.
  func acquire(timeoutMs: Int64) -> Int64? {
    let start = clock()
    let deadline = start &+ UInt64(max(0, timeoutMs)) * 1_000_000
    condition.lock()
    defer { condition.unlock() }
    while true {
      let now = clock()
      if current == 0 || now >= expiresAt {
        current = nextId
        nextId += 1
        expiresAt = now &+ ttlNanos
        return current
      }
      if now >= deadline { return nil }
      let waitNanos = min(deadline - now, expiresAt - now)
      _ = condition.wait(until: Date(timeIntervalSinceNow: Double(waitNanos) / 1e9))
    }
  }

  /// Releases `lease`; a stale or unknown lease is ignored.
  func release(_ lease: Int64) {
    condition.lock()
    defer { condition.unlock() }
    if lease != 0 && lease == current {
      current = 0
      condition.broadcast()
    }
  }

  /// T-016 (S-2, FU-065): if `lease` is the current, unexpired lease, sets its
  /// expiry to now + `ttlNanos` and returns true; otherwise false. Never takes
  /// a lease. Same-lease renewals are unbounded, but an engine that stops
  /// renewing still loses the lease `ttlNanos` after its last renewal.
  func renew(_ lease: Int64) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    let now = clock()
    guard lease != 0 && lease == current && now < expiresAt else { return false }
    expiresAt = now &+ ttlNanos
    return true
  }

  /// True while `lease` is the current, unexpired lease.
  func isValid(_ lease: Int64) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    return lease != 0 && lease == current && clock() < expiresAt
  }
}
