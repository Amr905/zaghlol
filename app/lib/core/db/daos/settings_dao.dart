// T-019: preferences and secure state (database-schema §2.8).
//
// `settings` holds every preference as text (typed accessors and defaults:
// T-020). `secure_state` holds tokens and the trusted-time state as BLOBs
// (security-model §3, backend-api §4.3): only in the encrypted DB, never in
// preferences, files, logs or errors. A refused write is a code-only
// DbWriteException (guardWrite), so a value never appears in an error.
// Nothing here logs. Keys are code constants (`[a-z0-9_.]`, 1–64).

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

class SettingsDao {
  SettingsDao(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async => (await (_db.select(
    _db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  /// Emits the value of [key] now and after every change (null: unset).
  Stream<String?> watch(String key) => (_db.select(
    _db.settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  /// Every setting, by key.
  Future<Map<String, String>> all() async => {
    for (final r in await _db.select(_db.settings).get()) r.key: r.value,
  };

  /// Sets [key] to [value] (≤ 16 KiB of text, no NUL).
  Future<void> write(String key, String value, {required int at}) => guardWrite(
    () => _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value, updatedAt: at),
        ),
  );

  Future<int> delete(String key) => guardWrite(
    () => (_db.delete(_db.settings)..where((s) => s.key.equals(key))).go(),
  );
}

class SecureStateDao {
  SecureStateDao(this._db);

  final AppDatabase _db;

  /// The value of [key], or null when unset. The caller owns the copy.
  Future<Uint8List?> read(String key) async => (await (_db.select(
    _db.secureState,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  /// Sets [key] to [value] (1 B–64 KiB).
  Future<void> write(String key, Uint8List value, {required int at}) =>
      guardWrite(
        () => _db
            .into(_db.secureState)
            .insertOnConflictUpdate(
              SecureStateCompanion.insert(
                key: key,
                value: value,
                updatedAt: at,
              ),
            ),
      );

  /// Sets [key] to [next] only if its current value is [expected] (null:
  /// only if unset), in one statement. Returns true when this call wrote:
  /// of two actors starting from the same value, exactly one wins.
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
    required int at,
  }) => guardWrite(() async {
    final int changed;
    if (expected == null) {
      changed = await _db.customUpdate(
        'INSERT INTO secure_state ("key", value, updated_at) '
        'VALUES (?1, ?2, ?3) ON CONFLICT DO NOTHING',
        variables: [
          Variable.withString(key),
          Variable.withBlob(next),
          Variable.withInt(at),
        ],
        updates: {_db.secureState},
        updateKind: UpdateKind.insert,
      );
    } else {
      changed = await _db.customUpdate(
        'UPDATE secure_state SET value = ?1, updated_at = ?2 '
        'WHERE "key" = ?3 AND value = ?4',
        variables: [
          Variable.withBlob(next),
          Variable.withInt(at),
          Variable.withString(key),
          Variable.withBlob(expected),
        ],
        updates: {_db.secureState},
        updateKind: UpdateKind.update,
      );
    }
    return changed == 1;
  });

  Future<int> delete(String key) => guardWrite(
    () => (_db.delete(_db.secureState)..where((s) => s.key.equals(key))).go(),
  );
}
