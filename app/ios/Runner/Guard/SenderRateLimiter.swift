import Foundation

/// Per-sender rate limit applied to `GuardDecision.keep` only (T-035 section
/// 4, FU-084b): more than `perSenderPerMin` keeps from one
/// `(channel, source key)` within a sliding 60 s window become
/// `rate_limited`. Port of Dart `sender_rate_limiter.dart` and Kotlin
/// `SenderRateLimiter` (same key, same boundary comparisons, LRU of
/// `maxKeys` keys).
///
/// In memory only, reset with the process: persisting it would write sender
/// ids to disk. Thread-safe (the intents may run concurrently). The clock is
/// monotonic milliseconds.
final class SenderRateLimiter {
  /// Dart `kGuardRateLimiterMaxKeys`.
  static let defaultMaxKeys = 64
  /// Dart `kGuardRateWindowMs`.
  static let windowMs: Int64 = 60_000

  let perSenderPerMin: Int
  let maxKeys: Int
  private let lock = NSLock()
  /// Least recently used first.
  private var order: [GuardUserSender] = []
  private var windows: [GuardUserSender: [Int64]] = [:]

  init(perSenderPerMin: Int, maxKeys: Int = SenderRateLimiter.defaultMaxKeys) {
    precondition(perSenderPerMin > 0 && maxKeys > 0)
    self.perSenderPerMin = perSenderPerMin
    self.maxKeys = maxKeys
  }

  /// Number of keys currently remembered (tests).
  var trackedKeys: Int {
    lock.lock()
    defer { lock.unlock() }
    return windows.count
  }

  /// Applies the limit to `decision` at monotonic time `nowMs`. Drops are
  /// returned unchanged and not counted.
  func apply(_ decision: GuardDecision, channel: String, source: String, nowMs: Int64)
    -> GuardDecision
  {
    guard case .keep = decision else { return decision }
    let units: [UInt16]
    if let ch = GuardChannel(rawValue: channel) {
      units = GuardConfig.sourceKey(ch, source)
    } else {
      units = TextFold.dartTrim(TextFold.units(source))
    }
    let key = GuardUserSender(channel: channel, key: units)
    lock.lock()
    defer { lock.unlock() }
    var window = windows[key] ?? []
    if let at = order.firstIndex(of: key) { order.remove(at: at) }
    order.append(key)
    if order.count > maxKeys {
      let evicted = order.removeFirst()
      windows[evicted] = nil
    }
    // A clock that went backwards (it should not: monotonic) restarts the
    // window rather than keeping stale counts forever.
    if let last = window.last, last > nowMs { window.removeAll() }
    while let first = window.first, nowMs - first >= SenderRateLimiter.windowMs {
      window.removeFirst()
    }
    if window.count >= perSenderPerMin {
      windows[key] = window
      return .drop(.rateLimited)
    }
    window.append(nowMs)
    windows[key] = window
    return decision
  }
}
