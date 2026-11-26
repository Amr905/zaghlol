// T-337: stores the last accepted sync `config` block in the encrypted
// `secure_state` table (wiped with the database by "Delete everything") and
// evaluates it: fresh -> typed values, missing/stale/unreadable -> defaults.
// A block with the same or a lower version than the stored one is ignored.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../db/daos/settings_dao.dart';
import 'remote_config.dart';

const String remoteConfigSnapshotKey = 'config.snapshot';
const int maxRemoteConfigSnapshotBytes = 8192;

final class RemoteConfigService {
  RemoteConfigService({
    required this._dao,
    required this._clock,
    this.maxAge = const Duration(days: 14),
  });

  final SecureStateDao _dao;
  final DateTime Function() _clock;
  final Duration maxAge;

  int _version = 0;
  int _atMs = 0;
  Map<String, String> _values = const {};
  LlmProviderNames? _names;
  bool _loaded = false;
  Future<void> _writes = Future<void>.value();
  final _changes = StreamController<RemoteConfig>.broadcast();

  /// Version of the stored block (0 when none): what the next sync may send
  /// as `configVersion`.
  int get version => _version;

  /// Typed values now; defaults when missing, stale or the clock is odd.
  RemoteConfig get current {
    if (!_loaded || _version == 0) return RemoteConfig.defaults;
    final age = _clock().toUtc().millisecondsSinceEpoch - _atMs;
    if (age < -const Duration(minutes: 5).inMilliseconds ||
        age >= maxAge.inMilliseconds) {
      return RemoteConfig.defaults;
    }
    return RemoteConfig.fromValues(_values, providerName: _names);
  }

  Stream<RemoteConfig> watch() async* {
    yield current;
    yield* _changes.stream;
  }

  Future<void> load() async {
    _loaded = true;
    try {
      final bytes = await _dao.read(remoteConfigSnapshotKey);
      if (bytes == null || bytes.length > maxRemoteConfigSnapshotBytes) return;
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['v'] != 1) return;
      final p = _parse(j['version'], j['values'], j['names']);
      final at = j['at'];
      if (p == null || at is! int) return;
      _version = p.version;
      _atMs = at;
      _values = p.values;
      _names = p.names;
    } on Object {
      // Unreadable: defaults. The next good block replaces it.
      _version = 0;
    }
  }

  /// Validates and stores a block. True when stored. Bad shape or an older or
  /// equal version keeps the previous values.
  Future<bool> apply({
    required Object? version,
    required Object? values,
    Object? providerName,
  }) {
    final run = _writes.then((_) async {
      final p = _parse(version, values, providerName);
      if (p == null || (_version > 0 && p.version <= _version)) return false;
      final now = _clock().toUtc().millisecondsSinceEpoch;
      await _dao.write(
        remoteConfigSnapshotKey,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'version': p.version,
              'at': now,
              'values': p.values,
              if (p.names != null)
                'names': {'ar': p.names!.ar, 'en': p.names!.en},
            }),
          ),
        ),
        at: now,
      );
      _version = p.version;
      _atMs = now;
      _values = p.values;
      _names = p.names;
      _loaded = true;
      _changes.add(current);
      return true;
    });
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// A successful sync that omitted `config` confirms the held [version]:
  /// freshness moves to now. Ignored when none is held or it differs.
  Future<void> confirm(int version) {
    final run = _writes.then((_) async {
      if (_version == 0 || _version != version) return;
      final now = _clock().toUtc().millisecondsSinceEpoch;
      if (now <= _atMs) return;
      await _dao.write(
        remoteConfigSnapshotKey,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'version': _version,
              'at': now,
              'values': _values,
              if (_names != null) 'names': {'ar': _names!.ar, 'en': _names!.en},
            }),
          ),
        ),
        at: now,
      );
      _atMs = now;
      _changes.add(current);
    });
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void dispose() => unawaited(_changes.close());

  static ({int version, Map<String, String> values, LlmProviderNames? names})?
  _parse(Object? version, Object? values, Object? names) {
    if (version is! int || version < 1 || values is! Map) return null;
    final out = <String, String>{};
    for (final e in values.entries) {
      if (e.key is! String || e.value is! String) return null;
      out[e.key as String] = e.value as String;
    }
    LlmProviderNames? n;
    if (names is Map && names['ar'] is String && names['en'] is String) {
      n = LlmProviderNames(
        ar: names['ar'] as String,
        en: names['en'] as String,
      );
    }
    return (version: version, values: out, names: n);
  }
}
