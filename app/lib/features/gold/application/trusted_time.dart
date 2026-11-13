// T-144: trusted time (backend-api §4.3 "Trusted time", R3-1, R4-3).
//
// The device's wall clock never decides Gold on its own. This file keeps the
// high-water mark `hw`, the uncharged lower bound `lb`, the monotonic reading
// and boot reference of the last write, and the `tampered` flag in one
// `secure_state` record, and advances them from clock samples. Only a fresh
// time-nonce echo (see time_anchor.dart) may lower `hw`/`lb` or clear
// `tampered`; every other signed time only raises them.
//
// Accepted residual 3 (security review): an iOS reboot that is neither
// proven by `m < mono` nor visible as a boot-reference shift is not detected
// and is not charged. No further heuristic is added (design note, T-144).
// On Android `BOOT_COUNT` may be null (FU-128): the monotonic-drop rule then
// applies, as on iOS.

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/backend/backend_state.dart';
import '../../../core/platform/clock_api.g.dart';

const int _minuteMs = 60 * 1000;
const int _hourMs = 60 * _minuteMs;
const int _tamperSlackMs = 10 * _minuteMs;
const int _rebootChargeMs = 6 * _hourMs;

/// The `secure_state` key of the trusted-time record.
const String trustedTimeStateKey = 'trusted_time';

/// One consistent clock sample.
final class ClockReading {
  const ClockReading({
    required this.wallMs,
    required this.monotonicMs,
    this.bootCount,
  });

  final int wallMs;
  final int monotonicMs;

  /// Android `BOOT_COUNT`; null on iOS and when Android withholds it.
  final int? bootCount;

  /// The boot reference: the count when there is one, else `wall - m`.
  int get bootRef => bootCount ?? (wallMs - monotonicMs);
  bool get bootIsCount => bootCount != null;
}

abstract interface class ClockSource {
  Future<ClockReading> sample();
}

/// Production source over `TrustedClockHostApi` (T-180).
final class HostClockSource implements ClockSource {
  HostClockSource([TrustedClockHostApi? api])
    : _api = api ?? TrustedClockHostApi();
  final TrustedClockHostApi _api;

  @override
  Future<ClockReading> sample() async {
    final s = await _api.sample();
    return ClockReading(
      wallMs: s.wallMs,
      monotonicMs: s.monotonicMs,
      bootCount: s.bootCount,
    );
  }
}

/// True when [now] is on the same boot as the reading `(boot, bootIsCount,
/// mono)` (same rule as the interval classes; used for the nonce echo).
bool sameBoot({
  required int boot,
  required bool bootIsCount,
  required int mono,
  required ClockReading now,
}) {
  if (now.monotonicMs < mono) return false;
  if (bootIsCount != now.bootIsCount) return false;
  if (bootIsCount) return now.bootRef == boot;
  return (now.bootRef - boot).abs() <= _tamperSlackMs;
}

final class TrustedTimeState {
  const TrustedTimeState({
    required this.hw,
    required this.lb,
    required this.mono,
    required this.boot,
    required this.bootIsCount,
    required this.lastServerTime,
    required this.tampered,
  });

  final int hw;
  final int lb;
  final int mono;
  final int boot;
  final bool bootIsCount;
  final int lastServerTime;
  final bool tampered;

  TrustedTimeState copyWith({
    int? hw,
    int? lb,
    int? mono,
    int? boot,
    bool? bootIsCount,
    int? lastServerTime,
    bool? tampered,
  }) => TrustedTimeState(
    hw: hw ?? this.hw,
    lb: lb ?? this.lb,
    mono: mono ?? this.mono,
    boot: boot ?? this.boot,
    bootIsCount: bootIsCount ?? this.bootIsCount,
    lastServerTime: lastServerTime ?? this.lastServerTime,
    tampered: tampered ?? this.tampered,
  );

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'hw': hw,
        'lb': lb,
        'mono': mono,
        'boot': boot,
        'bc': bootIsCount,
        'ls': lastServerTime,
        't': tampered,
      }),
    ),
  );

  /// Null for anything that is not a well-formed record.
  static TrustedTimeState? decode(Uint8List bytes) {
    try {
      final m = jsonDecode(utf8.decode(bytes));
      if (m is! Map || m['v'] != 1) return null;
      final hw = m['hw'];
      final lb = m['lb'];
      final mono = m['mono'];
      final boot = m['boot'];
      final bc = m['bc'];
      final ls = m['ls'];
      final t = m['t'];
      if (hw is! int ||
          lb is! int ||
          mono is! int ||
          boot is! int ||
          bc is! bool ||
          ls is! int ||
          t is! bool ||
          lb > hw) {
        return null;
      }
      return TrustedTimeState(
        hw: hw,
        lb: lb,
        mono: mono,
        boot: boot,
        bootIsCount: bc,
        lastServerTime: ls,
        tampered: t,
      );
    } on Object {
      return null;
    }
  }
}

/// The trusted-time engine. Reads and writes the record on every call
/// (compare-and-set, so two engines cannot silently overwrite each other),
/// and serializes its own calls.
final class TrustedTime {
  TrustedTime({required this._store, required this._clock});

  final BackendStateStore _store;
  final ClockSource _clock;
  Future<void> _tail = Future<void>.value();

  Future<R> _serial<R>(Future<R> Function() f) {
    final next = _tail.then((_) => f());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// A fresh sample of the clock source (for the anchor service).
  Future<ClockReading> sample() => _clock.sample();

  /// Advances the record to [reading] (or a fresh sample) and returns it.
  Future<TrustedTimeState> advance([ClockReading? reading]) =>
      _serial(() async {
        final r = reading ?? await _clock.sample();
        return _update((s) => s == null ? _initial(r) : _advance(s, r));
      });

  /// A signed server time that is **not** a fresh echo: raise only.
  Future<TrustedTimeState> raise({
    required int serverTimeMs,
    int? iatMs,
    ClockReading? reading,
  }) => _serial(() async {
    final r = reading ?? await _clock.sample();
    return _update((cur) {
      final s = cur == null ? _initial(r) : _advance(cur, r);
      final top = [s.hw, serverTimeMs, ?iatMs].reduce((a, b) => a > b ? a : b);
      final lbTop = [
        s.lb,
        serverTimeMs,
        ?iatMs,
      ].reduce((a, b) => a > b ? a : b);
      return s.copyWith(
        hw: top,
        lb: lbTop,
        lastServerTime: serverTimeMs > s.lastServerTime
            ? serverTimeMs
            : s.lastServerTime,
      );
    });
  });

  /// A fresh echo: the only way to lower `hw`/`lb` or clear `tampered`.
  Future<TrustedTimeState> reanchor({
    required int serverTimeMs,
    ClockReading? reading,
  }) => _serial(() async {
    final r = reading ?? await _clock.sample();
    return _update((cur) {
      final last = cur?.lastServerTime ?? 0;
      return TrustedTimeState(
        hw: serverTimeMs,
        lb: serverTimeMs,
        mono: r.monotonicMs,
        boot: r.bootRef,
        bootIsCount: r.bootIsCount,
        lastServerTime: serverTimeMs > last ? serverTimeMs : last,
        tampered: false,
      );
    });
  });

  /// The stored record without advancing (null when none).
  Future<TrustedTimeState?> peek() async {
    final b = await _store.read(trustedTimeStateKey);
    return b == null ? null : TrustedTimeState.decode(b);
  }

  TrustedTimeState _initial(ClockReading r) => TrustedTimeState(
    hw: r.wallMs,
    lb: r.wallMs,
    mono: r.monotonicMs,
    boot: r.bootRef,
    bootIsCount: r.bootIsCount,
    lastServerTime: 0,
    tampered: false,
  );

  Future<TrustedTimeState> _update(
    TrustedTimeState Function(TrustedTimeState? current) f,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final bytes = await _store.read(trustedTimeStateKey);
      TrustedTimeState? cur;
      if (bytes != null) {
        cur = TrustedTimeState.decode(bytes);
        // Present but unreadable: not proof of anything, but Gold cannot be
        // trusted until a fresh echo. Keep nothing of the old value.
        cur ??= TrustedTimeState(
          hw: 0,
          lb: 0,
          mono: 0,
          boot: 0,
          bootIsCount: false,
          lastServerTime: 0,
          tampered: true,
        );
      }
      final next = f(cur);
      final ok = await _store.compareAndSet(
        trustedTimeStateKey,
        expected: bytes,
        next: next.encode(),
      );
      if (ok) return next;
    }
    // Lost the race four times: the other writer's value is at least as new.
    final bytes = await _store.read(trustedTimeStateKey);
    final cur = bytes == null ? null : TrustedTimeState.decode(bytes);
    return cur ??
        const TrustedTimeState(
          hw: 0,
          lb: 0,
          mono: 0,
          boot: 0,
          bootIsCount: false,
          lastServerTime: 0,
          tampered: true,
        );
  }

  TrustedTimeState _advance(TrustedTimeState s, ClockReading r) {
    final m = r.monotonicMs;
    final w = r.wallMs;
    final int lower;
    final int charge;
    if (s.bootIsCount != r.bootIsCount) {
      // The kind of boot reference changed (BOOT_COUNT appeared or went
      // missing): cannot compare, charge conservatively.
      lower = m >= s.mono ? m - s.mono : m;
      charge = lower > _rebootChargeMs ? lower : _rebootChargeMs;
    } else if (r.bootIsCount) {
      if (r.bootRef == s.boot && m >= s.mono) {
        lower = m - s.mono;
        charge = lower;
      } else {
        lower = m;
        charge = m > _rebootChargeMs ? m : _rebootChargeMs;
      }
    } else if (m < s.mono) {
      lower = m;
      charge = m > _rebootChargeMs ? m : _rebootChargeMs;
    } else if ((r.bootRef - s.boot).abs() > _tamperSlackMs) {
      lower = m - s.mono;
      charge = lower > _rebootChargeMs ? lower : _rebootChargeMs;
    } else {
      lower = m - s.mono;
      charge = lower;
    }

    final bound = s.lb + lower;
    final failed = w < bound - _tamperSlackMs;
    final lb = failed ? bound : (bound > w ? bound : w);
    final hwCharged = s.hw + charge;
    final hw = hwCharged > lb ? hwCharged : lb;
    return s.copyWith(
      hw: hw,
      lb: lb,
      mono: m,
      boot: r.bootRef,
      bootIsCount: r.bootIsCount,
      tampered: s.tampered || failed,
    );
  }
}
