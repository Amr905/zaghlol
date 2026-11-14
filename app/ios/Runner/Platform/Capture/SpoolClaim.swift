import Foundation

/// Process-wide drain claim (mirror of the Android `SpoolClaim`): spool
/// entries are handed to one engine at a time, so the UI engine and a
/// headless engine (App Intent, BGAppRefreshTask) never process the same
/// entry concurrently. The claim belongs to the engine whose host drained
/// last; it is released when that engine acks everything it drained, when it
/// detaches, or `ttlMs` after the last drain.
final class SpoolClaim {
  static let process = SpoolClaim()
  static let ttlMs: Int64 = 60_000

  private let lock = NSLock()
  private let clock: () -> Int64
  private let ttl: Int64
  private var owner: Int64?
  private var expiresAt: Int64 = 0
  private var held = Set<String>()

  init(
    clock: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
    ttlMs: Int64 = SpoolClaim.ttlMs
  ) {
    self.clock = clock
    self.ttl = ttlMs
  }

  /// Takes or renews the claim for `engine`; false while another engine holds an unexpired claim.
  func acquire(_ engine: Int64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let current = owner, current != engine, clock() < expiresAt { return false }
    if owner != engine { held.removeAll() }
    owner = engine
    expiresAt = clock() + ttl
    return true
  }

  /// Records the ids `engine` just drained; ignored unless it owns the claim.
  func hold(_ engine: Int64, _ ids: [String]) {
    lock.lock()
    defer { lock.unlock() }
    guard owner == engine else { return }
    held.formUnion(ids)
    if held.isEmpty { releaseLocked(engine) }
  }

  /// `engine` acked `ids`; the claim is released once nothing it drained is left.
  func acked(_ engine: Int64, _ ids: [String]) {
    lock.lock()
    defer { lock.unlock() }
    guard owner == engine else { return }
    held.subtract(ids)
    if held.isEmpty { releaseLocked(engine) }
  }

  /// Engine detached (or gave up): drops its claim, never another engine's.
  func release(_ engine: Int64) {
    lock.lock()
    defer { lock.unlock() }
    releaseLocked(engine)
  }

  func ownerOrNil() -> Int64? {
    lock.lock()
    defer { lock.unlock() }
    guard let current = owner else { return nil }
    if clock() >= expiresAt {
      owner = nil
      held.removeAll()
      return nil
    }
    return current
  }

  private func releaseLocked(_ engine: Int64) {
    guard owner == engine else { return }
    owner = nil
    held.removeAll()
    expiresAt = 0
  }
}
