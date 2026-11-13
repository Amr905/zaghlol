// T-143: when the daily sync may run (EC-43, FR-SYNC-01). Pure Dart.
//
// The server decides the window (`nextSyncNotBefore`, server time); the app
// only estimates the server's "now" as the last answer's `serverTime` plus the
// wall time that passed since it arrived. A wall clock that moved backwards
// makes the sync due (the server throttles it anyway, so a wrong clock can't
// hammer the API). After a failure at most one attempt per hour, growing to
// eight hours, never earlier than the server's `Retry-After`.

import 'dart:convert';
import 'dart:typed_data';

const int _hourMs = 60 * 60 * 1000;

/// Shortest wait after a failed attempt.
const Duration syncMinBackoff = Duration(hours: 1);

/// Longest wait after repeated failures (without a longer `Retry-After`).
const Duration syncMaxBackoff = Duration(hours: 8);

/// The wait after [failures] failed attempts in a row (>= 1), at least
/// [retryAfter] when the server gave one (capped at one day).
Duration syncBackoff(int failures, {Duration? retryAfter}) {
  final n = failures < 1 ? 1 : failures;
  final shift = n > 4 ? 4 : n - 1;
  var ms = _hourMs * (1 << shift);
  if (ms > syncMaxBackoff.inMilliseconds) ms = syncMaxBackoff.inMilliseconds;
  final ra = retryAfter == null
      ? 0
      : (retryAfter > const Duration(days: 1)
                ? const Duration(days: 1)
                : retryAfter)
            .inMilliseconds;
  return Duration(milliseconds: ra > ms ? ra : ms);
}

/// What the sync remembers between runs (never financial data).
final class SyncState {
  const SyncState({
    this.lastOkWallMs,
    this.serverMs,
    this.wallAtServerMs,
    this.nextNotBeforeServerMs,
    this.failures = 0,
    this.retryNotBeforeWallMs,
    this.pendingFullVersion,
  });

  static const SyncState empty = SyncState();

  /// Wall time of the last effective sync (for the About line).
  final int? lastOkWallMs;

  /// `serverTime` of the last answer (effective or throttle).
  final int? serverMs;

  /// Wall time when that answer arrived.
  final int? wallAtServerMs;

  /// `nextSyncNotBefore` of the last answer (server time).
  final int? nextNotBeforeServerMs;

  /// Failed attempts in a row.
  final int failures;

  /// No new attempt before this wall time (back-off).
  final int? retryNotBeforeWallMs;

  /// A catalog snapshot that still has to be downloaded.
  final int? pendingFullVersion;

  SyncState copyWith({
    int? lastOkWallMs,
    int? serverMs,
    int? wallAtServerMs,
    int? nextNotBeforeServerMs,
    int? failures,
    Object? retryNotBeforeWallMs = _keep,
    Object? pendingFullVersion = _keep,
  }) => SyncState(
    lastOkWallMs: lastOkWallMs ?? this.lastOkWallMs,
    serverMs: serverMs ?? this.serverMs,
    wallAtServerMs: wallAtServerMs ?? this.wallAtServerMs,
    nextNotBeforeServerMs: nextNotBeforeServerMs ?? this.nextNotBeforeServerMs,
    failures: failures ?? this.failures,
    retryNotBeforeWallMs: identical(retryNotBeforeWallMs, _keep)
        ? this.retryNotBeforeWallMs
        : retryNotBeforeWallMs as int?,
    pendingFullVersion: identical(pendingFullVersion, _keep)
        ? this.pendingFullVersion
        : pendingFullVersion as int?,
  );

  static const Object _keep = Object();

  /// False while a back-off is running at wall time [nowWallMs].
  bool retryAllowed(int nowWallMs) {
    final retry = retryNotBeforeWallMs;
    // A retry time further away than the longest back-off means the wall
    // clock was moved back: don't wait on it.
    return !(retry != null &&
        retry > nowWallMs &&
        retry - nowWallMs <= syncMaxBackoff.inMilliseconds + _hourMs);
  }

  /// Whether a request may go out at wall time [nowWallMs].
  bool isDue(int nowWallMs) {
    if (!retryAllowed(nowWallMs)) return false;
    final next = nextNotBeforeServerMs;
    final server = serverMs;
    final wall = wallAtServerMs;
    if (next == null || server == null || wall == null) return true;
    final elapsed = nowWallMs - wall;
    if (elapsed < 0) return true;
    return server + elapsed >= next;
  }

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        if (lastOkWallMs != null) 'ok': lastOkWallMs,
        if (serverMs != null) 'sm': serverMs,
        if (wallAtServerMs != null) 'wm': wallAtServerMs,
        if (nextNotBeforeServerMs != null) 'nb': nextNotBeforeServerMs,
        'f': failures,
        if (retryNotBeforeWallMs != null) 'rt': retryNotBeforeWallMs,
        if (pendingFullVersion != null) 'pf': pendingFullVersion,
      }),
    ),
  );

  /// Reads stored bytes; anything unreadable is [empty] (the next sync simply
  /// runs, and the server's own throttle still applies).
  static SyncState decode(Uint8List? bytes) {
    if (bytes == null || bytes.length > 1024) return empty;
    try {
      final m = jsonDecode(utf8.decode(bytes));
      if (m is! Map || m['v'] != 1) return empty;
      int? i(String k) {
        final v = m[k];
        return v is int ? v : null;
      }

      final f = i('f');
      return SyncState(
        lastOkWallMs: i('ok'),
        serverMs: i('sm'),
        wallAtServerMs: i('wm'),
        nextNotBeforeServerMs: i('nb'),
        failures: f == null || f < 0 ? 0 : f,
        retryNotBeforeWallMs: i('rt'),
        pendingFullVersion: i('pf'),
      );
    } on FormatException {
      return empty;
    }
  }
}
