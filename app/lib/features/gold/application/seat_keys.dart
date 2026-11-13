// T-179: the Dart side of the iOS seat keys (D-55, D-62, R4-1(1), R5-6;
// platform-channels §4b; design note in docs/04-tasks/tasks/T-179.md §5).
//
// - Android, no install yet, `SEAT_KEY_UNAVAILABLE`, any other platform error
//   or a malformed native answer: no keys (requests then carry no `seatKeys`).
// - Install binding: `seat_key_install` holds the install ID the native own
//   key belongs to. A different install ID (first run, reinstall, "Delete
//   everything", R5-1 re-registration) rotates the keys first, so element 0
//   stays the same for the whole life of an install.
// - R5-6: `seat_key_unusable` holds the install ID it was set for; while it
//   equals the current install ID, no keys are returned. `InstallReregistered`
//   deletes it.
//
// Nothing here logs: public keys and signatures never reach the diag log or
// any error text.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/platform/seat_key_api.g.dart';
import '../domain/binding/request_binding.dart';

/// `secure_state` key: the install ID the native own key belongs to.
const String seatKeyInstallStateKey = 'seat_key_install';

/// `secure_state` key: "own seat key unusable for this install" (R5-6); the
/// value is that install's ID.
const String seatKeyUnusableStateKey = 'seat_key_unusable';

/// The only error code of `SeatKeyHostApi`.
const String seatKeyUnavailableCode = 'SEAT_KEY_UNAVAILABLE';

const int _maxSeatKeys = 5;
const int _signatureLength = 64;

final class SeatKeyService {
  SeatKeyService({
    required this._platform,
    required this._store,
    required this._installId,
    SeatKeyHostApi? host,
  }) : _hostOrNull = host;

  final ClientPlatform _platform;
  final BackendStateStore _store;
  final Future<String?> Function() _installId;
  final SeatKeyHostApi? _hostOrNull;

  // Created only on iOS; an Android build never opens the channel.
  late final SeatKeyHostApi _host = _hostOrNull ?? SeatKeyHostApi();

  StreamSubscription<BackendEvent>? _events;
  Future<void> _tail = Future<void>.value();

  /// Listens for `InstallReregistered` (drops the R5-6 flag).
  void start(Stream<BackendEvent> events) {
    _events ??= events.listen((e) {
      if (e is InstallReregistered) unawaited(_serial(_onReregistered));
    });
  }

  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
  }

  /// [own, earlier…] public keys (65 bytes each), or none.
  Future<List<Uint8List>> publicKeys() => _serial(() async {
    if (await _prepare() == null) return const [];
    try {
      final keys = await _host.publicKeys();
      return _validKeys(keys) ? List.unmodifiable(keys) : const [];
    } on PlatformException {
      return const [];
    }
  });

  /// The seat proofs for [op] over [challenge] (32 bytes), own key first, or
  /// none. The message is built here (T-183) with this install's ID.
  Future<List<SeatSignature>> prove(SeatOp op, Uint8List challenge) =>
      _serial(() async {
        final installId = await _prepare();
        if (installId == null) return const [];
        final message = seatMessage(op, installId, challenge);
        try {
          final out = await _host.sign(message);
          final keys = [for (final s in out) s.publicKey];
          final ok =
              _validKeys(keys) &&
              out.every((s) => s.signature.length == _signatureLength);
          return ok ? List.unmodifiable(out) : const [];
        } on PlatformException {
          return const [];
        }
      });

  /// R5-6: called by T-145/T-147 after a `SEAT_KEY_MISMATCH` confirmed by a
  /// successful retry without `seatKeys`.
  Future<void> markOwnKeyUnusable() => _serial(() async {
    final id = await _installId();
    if (id == null) return;
    await _store.write(seatKeyUnusableStateKey, _bytes(id));
  });

  /// True while the R5-6 flag applies to the current install.
  Future<bool> ownKeyUnusable() => _serial(() async {
    final id = await _installId();
    return id != null && await _flagFor(id);
  });

  /// "Delete everything" (R4-8): the own key becomes an earlier key. False
  /// when the native side could not do it (the next use retries through the
  /// install binding). No-op on Android.
  Future<bool> rotateForNewInstall() => _serial(() async {
    if (_platform != ClientPlatform.ios) return true;
    try {
      await _host.rotateForNewInstall();
    } on PlatformException {
      return false;
    }
    await _store.delete(seatKeyInstallStateKey);
    return true;
  });

  // ---- private ----

  /// The current install ID when keys may be used; rotates first when the
  /// native own key belongs to another install.
  Future<String?> _prepare() async {
    if (_platform != ClientPlatform.ios) return null;
    final id = await _installId();
    if (id == null) return null;
    if (await _flagFor(id)) return null;
    final bound = await _store.read(seatKeyInstallStateKey);
    final want = _bytes(id);
    if (bound == null || !_equal(bound, want)) {
      try {
        await _host.rotateForNewInstall();
      } on PlatformException {
        return null;
      }
      // Only after a successful rotation: a crash before this write rotates
      // again next time, which is a no-op until a new own key exists.
      await _store.write(seatKeyInstallStateKey, want);
    }
    return id;
  }

  Future<bool> _flagFor(String id) async {
    final flag = await _store.read(seatKeyUnusableStateKey);
    return flag != null && _equal(flag, _bytes(id));
  }

  Future<void> _onReregistered() async {
    final flag = await _store.read(seatKeyUnusableStateKey);
    if (flag == null) return;
    final id = await _installId();
    if (id != null && _equal(flag, _bytes(id))) return; // set for the new one
    await _store.deleteIfEquals(seatKeyUnusableStateKey, flag);
  }

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  static bool _validKeys(List<Uint8List> keys) {
    if (keys.length > _maxSeatKeys) return false;
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      if (k.length != seatPublicKeyLength || k[0] != 0x04) return false;
      for (var j = 0; j < i; j++) {
        if (_equal(keys[j], k)) return false;
      }
    }
    return true;
  }

  static Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'SeatKeyService';
}

/// Must be overridden where the backend client is wired (T-143/T-145).
final seatKeyServiceProvider = Provider<SeatKeyService>(
  (ref) => throw UnimplementedError('seatKeyServiceProvider not wired'),
);
