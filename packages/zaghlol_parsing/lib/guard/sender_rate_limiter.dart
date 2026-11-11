import 'dart:collection';

import 'guard_config.dart';
import 'guard_types.dart';

/// Most `(channel, sender)` keys the limiter remembers; the least recently
/// used one is forgotten beyond it.
const int kGuardRateLimiterMaxKeys = 64;

/// Length of the sliding window.
const int kGuardRateWindowMs = 60 * 1000;

/// Per-sender rate limit applied to [GuardKeep] decisions only (T-035 §4,
/// FU-084b): more than [perSenderPerMin] keeps from one `(channel, source
/// key)` within a sliding 60 s window become `rate_limited`.
///
/// In memory only and reset with the process: persisting it would write
/// sender ids to disk. Not thread-safe; one per Guard instance.
final class SenderRateLimiter {
  SenderRateLimiter(
    this.perSenderPerMin, {
    this.maxKeys = kGuardRateLimiterMaxKeys,
  }) : assert(perSenderPerMin > 0),
       assert(maxKeys > 0);

  final int perSenderPerMin;
  final int maxKeys;

  // Insertion order = recency (a touched key is re-inserted).
  final LinkedHashMap<(String, String), ListQueue<int>> _windows =
      LinkedHashMap();

  /// Number of keys currently remembered (for tests).
  int get trackedKeys => _windows.length;

  /// Applies the limit to [decision] at monotonic time [nowMonotonicMs].
  /// Drops are returned unchanged and not counted.
  GuardDecision apply(
    GuardDecision decision, {
    required String channel,
    required String source,
    required int nowMonotonicMs,
  }) {
    if (decision is! GuardKeep) {
      return decision;
    }
    final ch = GuardChannel.fromWire(channel);
    final key = (
      channel,
      ch == null ? source.trim() : guardSourceKey(ch, source),
    );
    var window = _windows.remove(key);
    window ??= ListQueue<int>();
    _windows[key] = window;
    if (_windows.length > maxKeys) {
      _windows.remove(_windows.keys.first);
    }
    // A clock that went backwards (it should not: monotonic) restarts the
    // window rather than keeping stale counts forever.
    if (window.isNotEmpty && window.last > nowMonotonicMs) {
      window.clear();
    }
    while (window.isNotEmpty &&
        nowMonotonicMs - window.first >= kGuardRateWindowMs) {
      window.removeFirst();
    }
    if (window.length >= perSenderPerMin) {
      return const GuardDrop(GuardDropReason.rateLimited);
    }
    window.addLast(nowMonotonicMs);
    return decision;
  }
}
