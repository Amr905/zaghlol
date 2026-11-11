// T-020: typed access to the `settings` table (database-schema §2.8). Every
// preference lives in the encrypted database through SettingsDao; nothing
// uses SharedPreferences or NSUserDefaults (FR-SEC-03; CI greps for them).
//
// Reads never fail on a bad stored value: it reads as the default. Writes are
// last-writer-wins per key (one upsert); a refused write is a code-only
// exception. Nothing here logs, and no error carries a value.

import '../db/daos/settings_dao.dart';
import 'setting_key.dart';

class SettingsRepository {
  SettingsRepository(this._dao, {int Function()? nowMs})
    : _nowMs = nowMs ?? _utcNowMs;

  final SettingsDao _dao;
  final int Function() _nowMs;

  static int _utcNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// The value of [key], or its default.
  Future<T> get<T>(SettingKey<T> key) async =>
      key.parse(await _dao.read(key.name));

  /// The value of [key] now and after every change to it.
  Stream<T> watch<T>(SettingKey<T> key) =>
      _dao.watch(key.name).distinct().map(key.parse);

  /// Sets [key]. A null (for a key with no default) unsets it. Throws
  /// [SettingsException] for an out-of-range value, writing nothing.
  Future<void> set<T>(SettingKey<T> key, T value) async {
    if (value == null) return reset(key);
    final text = key.format(value);
    await _dao.write(key.name, text, at: _nowMs());
  }

  /// Back to the default.
  Future<void> reset<T>(SettingKey<T> key) => _dao.delete(key.name);
}
