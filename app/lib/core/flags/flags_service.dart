// T-025: the feature-flags service. Holds the last verified snapshot from the
// daily sync in `secure_state`, evaluates it fail-closed and publishes
// changes so the UI follows without a restart.
//
// Rules:
// - Never synced, unknown, missing, malformed, stale or unverifiable: OFF.
// - A snapshot is accepted only if it parses strictly (known keys, bool
//   values, version int >= 0) and its version is not lower than the stored
//   one (a replayed older response cannot turn a flag back ON).
// - Staleness: older than [FlagsService.maxAge] by the app clock reads OFF.
//   A clock earlier than the snapshot's own time reads OFF too (unverifiable).
//   Residual: the app clock is not the trusted clock (T-144); a user who
//   sets the clock back can keep a snapshot fresh on their own phone only.
// - Turning a flag off hides the feature only. Nothing here deletes data
//   (EC-49); the service has no delete path at all.
// - Nothing is logged; errors carry codes only.

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../db/daos/settings_dao.dart';
import 'feature_flags.dart';

/// The `secure_state` key of the snapshot.
const String flagsSnapshotKey = 'flags.snapshot';

/// Largest snapshot we parse (the real one is under 1 KiB).
const int maxFlagsSnapshotBytes = 4096;

/// Where the snapshot lives. [SecureStateFlagStore] is the real one.
abstract interface class FlagSnapshotStore {
  Future<Uint8List?> read();
  Future<void> write(Uint8List bytes, {required int at});
}

/// The snapshot in the encrypted `secure_state` table.
final class SecureStateFlagStore implements FlagSnapshotStore {
  SecureStateFlagStore(this._dao);
  final SecureStateDao _dao;

  @override
  Future<Uint8List?> read() => _dao.read(flagsSnapshotKey);

  @override
  Future<void> write(Uint8List bytes, {required int at}) =>
      _dao.write(flagsSnapshotKey, bytes, at: at);
}

/// Flags as the backend sent them (`flags` block of `POST /v1/sync`). The
/// values are untrusted until [FlagsService.apply] validated them.
final class RemoteFlags {
  const RemoteFlags({required this.version, required this.values});
  final Object? version;
  final Object? values;
}

/// The failure of a [RemoteFlagsSource]. Code only.
final class FlagsUnavailable implements Exception {
  const FlagsUnavailable();
  @override
  String toString() => 'FlagsUnavailable';
}

/// The narrow port to the backend (the BackendClient, T-141, implements it).
/// Throws [FlagsUnavailable] when offline, unverified or refused.
abstract interface class RemoteFlagsSource {
  Future<RemoteFlags> fetch();
}

enum FlagsApplyResult {
  /// Stored and published.
  applied,

  /// Malformed, or older than the stored snapshot: nothing changed.
  rejected,

  /// No source, or it was unavailable: nothing changed.
  unavailable,
}

final class FlagsService {
  FlagsService({
    required FlagSnapshotStore store,
    required DateTime Function() clock,
    RemoteFlagsSource? remote,
    this.maxAge = const Duration(days: 14),
    this.clockTolerance = const Duration(minutes: 5),
  }) : _store = store,
       _clock = clock,
       _remote = remote;

  /// Past this age a snapshot reads OFF. The app syncs daily, so two weeks
  /// is about two weeks offline.
  final Duration maxAge;

  /// How far the clock may sit before the snapshot's time.
  final Duration clockTolerance;

  final FlagSnapshotStore _store;
  final DateTime Function() _clock;
  final RemoteFlagsSource? _remote;

  final _controller = StreamController<FeatureFlagsState>.broadcast();
  _Snapshot? _snapshot;
  bool _unverifiable = false;
  FeatureFlagsState _state = FeatureFlagsState.neverSynced;
  Timer? _expiry;
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  /// The flags now (re-evaluated against the clock).
  FeatureFlagsState get current {
    _evaluate();
    return _state;
  }

  /// Emits whenever the evaluated flags change. Not replayed: read [current].
  Stream<FeatureFlagsState> get changes => _controller.stream;

  /// The current flags, then every change. Subscribes to the changes in the
  /// same step as it reads the current value, so no change falls in a gap.
  Stream<FeatureFlagsState> watch() {
    late final StreamController<FeatureFlagsState> out;
    StreamSubscription<FeatureFlagsState>? sub;
    out = StreamController<FeatureFlagsState>(
      onListen: () {
        sub = changes.listen(out.add);
        out.add(current);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  bool isOn(FeatureFlag flag) => current.isOn(flag);

  /// Reads the stored snapshot. A read or parse failure leaves everything OFF
  /// ([FlagsStatus.unverifiable]) and keeps the stored bytes.
  Future<void> load() async {
    Uint8List? bytes;
    try {
      bytes = await _store.read();
    } on Exception {
      // Fail closed: an unreadable snapshot is not "no flags", it is OFF.
      _unverifiable = true;
      _evaluate();
      return;
    }
    if (bytes == null) {
      _snapshot = null;
      _unverifiable = false;
    } else {
      final s = _Snapshot.decode(bytes);
      _snapshot = s;
      _unverifiable = s == null;
    }
    _evaluate();
  }

  /// Fetches from the remote source and applies the answer.
  Future<FlagsApplyResult> refresh() async {
    final remote = _remote;
    if (remote == null) return FlagsApplyResult.unavailable;
    final RemoteFlags fetched;
    try {
      fetched = await remote.fetch();
    } on FlagsUnavailable {
      return FlagsApplyResult.unavailable;
    }
    return apply(fetched);
  }

  /// Validates and stores [flags] (the sync path), then publishes. Writes run
  /// one at a time, so two syncs cannot interleave their check and write.
  Future<FlagsApplyResult> apply(RemoteFlags flags) {
    final run = _writes.then((_) => _apply(flags));
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<FlagsApplyResult> _apply(RemoteFlags flags) async {
    final parsed = _validate(flags);
    if (parsed == null) return FlagsApplyResult.rejected;
    final stored = _snapshot;
    if (stored != null && parsed.version < stored.version) {
      return FlagsApplyResult.rejected;
    }
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final snap = _Snapshot(parsed.version, now, parsed.values);
    await _store.write(snap.encode(), at: now);
    _snapshot = snap;
    _unverifiable = false;
    _evaluate();
    return FlagsApplyResult.applied;
  }

  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    unawaited(_controller.close());
  }

  void _evaluate() {
    final next = _compute();
    _scheduleExpiry();
    if (next != _state) {
      _state = next;
      if (!_disposed) _controller.add(next);
    } else {
      _state = next;
    }
  }

  FeatureFlagsState _compute() {
    if (_unverifiable) return FeatureFlagsState.unverifiable;
    final s = _snapshot;
    if (s == null) return FeatureFlagsState.neverSynced;
    final age = _clock().toUtc().millisecondsSinceEpoch - s.fetchedAtMs;
    if (age < -clockTolerance.inMilliseconds) {
      return FeatureFlagsState.unverifiable;
    }
    if (age >= maxAge.inMilliseconds) return FeatureFlagsState.stale(s.version);
    return FeatureFlagsState.fresh(s.version, s.values);
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final s = _snapshot;
    if (_disposed || _unverifiable || s == null) return;
    final left =
        s.fetchedAtMs + maxAge.inMilliseconds - _clock().millisecondsSinceEpoch;
    if (left <= 0 || left > 0x7fffffff) return;
    _expiry = Timer(Duration(milliseconds: left), _evaluate);
  }
}

({int version, Map<FeatureFlag, bool> values})? _validate(RemoteFlags f) {
  final version = f.version;
  final values = f.values;
  if (version is! int || version < 0 || values is! Map) return null;
  final out = <FeatureFlag, bool>{};
  for (final e in values.entries) {
    final key = e.key;
    if (key is! String) return null;
    final flag = FeatureFlag.fromKey(key);
    if (flag == null) continue; // unknown flags are ignored (OFF)
    final v = e.value;
    if (v is! bool) return null;
    out[flag] = v;
  }
  return (version: version, values: out);
}

final class _Snapshot {
  _Snapshot(this.version, this.fetchedAtMs, this.values);
  final int version;
  final int fetchedAtMs;
  final Map<FeatureFlag, bool> values;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'version': version,
        'at': fetchedAtMs,
        'values': {for (final e in values.entries) e.key.key: e.value},
      }),
    ),
  );

  /// Strict decode; null for anything not exactly what [encode] writes.
  static _Snapshot? decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFlagsSnapshotBytes) return null;
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['v'] != 1) return null;
      final version = j['version'];
      final at = j['at'];
      final values = j['values'];
      if (version is! int || version < 0 || at is! int || values is! Map) {
        return null;
      }
      final v = _validate(RemoteFlags(version: version, values: values));
      if (v == null) return null;
      return _Snapshot(v.version, at, v.values);
    } on FormatException {
      return null;
    }
  }
}
