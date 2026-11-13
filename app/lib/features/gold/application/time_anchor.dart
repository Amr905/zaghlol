// T-144: the time-anchor service (backend-api §4.3 "Sending an anchoring
// request", R4-2).
//
// One service serializes the six anchoring requests. For each it draws a
// fresh 128-bit nonce from a CSPRNG, remembers `pending = {nonce, sentMono,
// sentBoot}` in memory only (one outstanding; a new request replaces it),
// and hands the nonce to the caller (T-141 sends it as `Zaghlol-Time-Nonce`).
// The nonce is never logged, never persisted and never leaves this object
// except in the request header.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/backend/ids.dart';
import 'trusted_time.dart';

/// A fresh echo must arrive within this long of sending (monotonic clock).
const Duration freshEchoWindow = Duration(seconds: 60);

final class _Pending {
  _Pending(this.nonce, this.sentMono, this.sentBoot, this.sentBootIsCount);
  final String nonce;
  final int sentMono;
  final int sentBoot;
  final bool sentBootIsCount;
}

final class TimeAnchor {
  TimeAnchor({required this._clock, Random? random})
    : _rng = random ?? Random.secure();

  final ClockSource _clock;
  final Random _rng;
  _Pending? _pending;
  Future<void> _tail = Future<void>.value();

  /// Whether a request is outstanding (tests; never exposes the value).
  bool get hasPending => _pending != null;

  /// Runs [request] with a fresh nonce, serialized with every other anchored
  /// request. [onResponse] runs inside the same critical section, so no newer
  /// request can replace `pending` before the answer was judged.
  Future<T> run<T>(
    Future<T> Function(TimeNonce nonce) request, {
    required Future<void> Function(T response) onResponse,
  }) {
    final next = _tail.then((_) async {
      final nonce = _draw();
      final s = await _clock.sample();
      _pending = _Pending(nonce, s.monotonicMs, s.bootRef, s.bootIsCount);
      final response = await request(TimeNonce(nonce));
      await onResponse(response);
      return response;
    });
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// True when [echoed] is the outstanding nonce, the answer arrived on the
  /// same boot and within [freshEchoWindow] of sending. Does not consume.
  bool isFreshEcho(String? echoed, ClockReading now) {
    final p = _pending;
    if (p == null || echoed == null || echoed != p.nonce) return false;
    if (!sameBoot(
      boot: p.sentBoot,
      bootIsCount: p.sentBootIsCount,
      mono: p.sentMono,
      now: now,
    )) {
      return false;
    }
    return now.monotonicMs - p.sentMono <= freshEchoWindow.inMilliseconds;
  }

  /// Single use: after a fresh echo was applied, the nonce is gone.
  void consume() => _pending = null;

  /// Drops the outstanding nonce (re-registration, shutdown).
  void clear() => _pending = null;

  String _draw() {
    final b = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      b[i] = _rng.nextInt(256);
    }
    return base64Url.encode(b).replaceAll('=', '');
  }
}
