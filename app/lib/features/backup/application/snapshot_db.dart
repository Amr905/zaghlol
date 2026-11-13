// T-149 (design note §3, §4): the SQLite work of a backup snapshot and a
// restore, on raw sqlite3mc connections opened with the app's keyed open
// sequence (encrypted_open.dart; nothing here issues `PRAGMA key`).
//
// Every function takes plain, sendable values (files, key material, ints),
// so the service can run it in a background isolate. The caller owns and
// zeroizes the key material; the copy sent to an isolate dies with it (the
// accepted T-015 §5 residual, as for drift's isolate). Every file written here
// is SQLCipher-encrypted (K_snap or K_db); `temp_store` is memory, so no
// sorter or VACUUM temp file reaches the disk.
//
// The only function that writes the live database is [swapIntoLive]: one
// SQLite backup into the live file, committed as one transaction.
//
// Failures are code-only BackupSnapshotExceptions: a SqliteException carries
// its statement, so none escapes. Nothing here logs.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sql;

import '../../../core/db/app_database.dart';
import '../../../core/db/encrypted_open.dart';
import '../../../core/db/key_bootstrap.dart' show DbKeyMaterial;
import 'backup_contents.dart';
import 'backup_snapshot_exception.dart';
import 'snapshot_tables.dart';

BackupSnapshotException _err(BackupSnapshotErrorCode c) =>
    BackupSnapshotException(c);

/// Opens [file] with [key] through the app's keyed sequence. [onKeyError]
/// is the code for a rejected key or failed open. The caller owns [key].
sql.Database _open(
  File file,
  DbKeyMaterial key,
  BackupSnapshotErrorCode onKeyError,
) {
  sql.Database? raw;
  try {
    raw = sql.sqlite3.open(file.path);
    applyBusyTimeout(raw);
    applyEncryptedOpenSequence(raw, key);
    applyAppPragmas(raw);
    return raw;
  } on Object {
    raw?.close();
    throw _err(onKeyError);
  }
}

/// Runs [body]; any SQLite or file error becomes [code]. A
/// BackupSnapshotException passes through.
T _guard<T>(BackupSnapshotErrorCode code, T Function() body) {
  try {
    return body();
  } on BackupSnapshotException {
    rethrow;
  } on Object {
    throw _err(code);
  }
}

Future<T> _guardAsync<T>(
  BackupSnapshotErrorCode code,
  Future<T> Function() body,
) async {
  try {
    return await body();
  } on BackupSnapshotException {
    rethrow;
  } on Object {
    throw _err(code);
  }
}

int _userVersion(sql.Database db) =>
    db.select('PRAGMA user_version').first.columnAt(0) as int;

int _pageSize(sql.Database db) =>
    db.select('PRAGMA page_size').first.columnAt(0) as int;

bool _integrityOk(sql.Database db) {
  final rows = db.select('PRAGMA integrity_check');
  return rows.length == 1 && rows.first.columnAt(0) == 'ok';
}

bool _foreignKeysOk(sql.Database db) =>
    db.select('PRAGMA foreign_key_check').isEmpty;

Set<String> _tableNames(sql.Database db) => {
  for (final r in db.select(
    "SELECT name FROM sqlite_schema WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  ))
    r.columnAt(0) as String,
};

/// Row counts of every ordinary (non-virtual) table.
Map<String, int> _tableCounts(sql.Database db) {
  final names = [
    for (final r in db.select(
      "SELECT name FROM sqlite_schema WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL%' "
      'ORDER BY name',
    ))
      r.columnAt(0) as String,
  ];
  return {
    for (final n in names)
      n: db.select('SELECT count(*) FROM "$n"').first.columnAt(0) as int,
  };
}

Map<String, String> _settingsOf(sql.Database db) {
  if (!_tableNames(db).contains('settings')) return const {};
  return {
    for (final r in db.select('SELECT "key", value FROM settings'))
      r.columnAt(0) as String: r.columnAt(1) as String,
  };
}

bool _sameMap<V>(Map<String, V> a, Map<String, V> b) =>
    a.length == b.length &&
    a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

/// What [buildSnapshot] produced.
final class SnapshotFacts {
  SnapshotFacts({
    required this.bytes,
    required this.schemaVersion,
    required this.settings,
    required this.tables,
  });

  final int bytes;
  final int schemaVersion;
  final Map<String, String> settings;
  final Map<String, int> tables;
}

/// Design note §3: copies the live database ([live], [liveKey]) into [out]
/// keyed with [snapKey] (SQLite backup API, one step = one consistent read
/// transaction), empties the device tables with secure_delete on, VACUUMs
/// and checks it. Reads the live file only.
Future<SnapshotFacts> buildSnapshot({
  required File live,
  required DbKeyMaterial liveKey,
  required File out,
  required DbKeyMaterial snapKey,
}) async {
  sql.Database? live0 = _open(
    live,
    liveKey,
    BackupSnapshotErrorCode.liveUnavailable,
  );
  sql.Database? snap;
  try {
    final src = live0;
    final version = _guard(
      BackupSnapshotErrorCode.liveUnavailable,
      () => _userVersion(src),
    );
    if (version != appSchemaVersion) {
      throw _err(BackupSnapshotErrorCode.liveUnavailable);
    }
    snap = _open(out, snapKey, BackupSnapshotErrorCode.io);
    final dst = snap;
    _guard(
      BackupSnapshotErrorCode.io,
      () => dst.execute('PRAGMA journal_mode = DELETE'),
    );
    await _guardAsync(
      BackupSnapshotErrorCode.io,
      () => src.backup(dst, nPage: -1).drain<void>(),
    );
    src.close();
    live0 = null;
    return _guard<SnapshotFacts>(BackupSnapshotErrorCode.io, () {
      dst.execute('PRAGMA secure_delete = ON');
      final present = _tableNames(dst);
      dst.execute('BEGIN IMMEDIATE');
      for (final t in deviceTables.reversed) {
        if (present.contains(t)) dst.execute('DELETE FROM "$t"');
      }
      dst.execute('COMMIT');
      dst.execute('VACUUM');
      if (!_integrityOk(dst) || _userVersion(dst) != appSchemaVersion) {
        throw _err(BackupSnapshotErrorCode.io);
      }
      final facts = SnapshotFacts(
        bytes: 0,
        schemaVersion: appSchemaVersion,
        settings: _settingsOf(dst),
        tables: _tableCounts(dst),
      );
      dst.close();
      snap = null;
      return SnapshotFacts(
        bytes: out.lengthSync(),
        schemaVersion: facts.schemaVersion,
        settings: facts.settings,
        tables: facts.tables,
      );
    });
  } finally {
    live0?.close();
    snap?.close();
  }
}

/// Design note §4 steps 4–5: checks the decrypted snapshot [snap] (keyed
/// with [snapKey]) against the authenticated header and the manifest, copies
/// it into [stage] under the device key [dbKey], migrates an older schema
/// with the app's own steps and checks the result against the current
/// schema. Never opens the live database. Deletes [snap] when done.
Future<void> stageRestore({
  required File snap,
  required DbKeyMaterial snapKey,
  required File stage,
  required DbKeyMaterial dbKey,
  required int headerSchemaVersion,
  required SnapshotManifest manifest,
  required Map<String, String> settings,
}) async {
  final src = _open(snap, snapKey, BackupSnapshotErrorCode.corruptContents);
  try {
    _guard(BackupSnapshotErrorCode.corruptContents, () {
      final v = _userVersion(src);
      if (v > appSchemaVersion) {
        throw _err(BackupSnapshotErrorCode.newerSchema);
      }
      if (v == 0 || v != headerSchemaVersion) {
        throw _err(BackupSnapshotErrorCode.corruptContents);
      }
      if (!_integrityOk(src) || !_foreignKeysOk(src)) {
        throw _err(BackupSnapshotErrorCode.corruptContents);
      }
      final present = _tableNames(src);
      for (final t in deviceTables) {
        if (!present.contains(t)) continue;
        final n = src.select('SELECT count(*) FROM "$t"').first.columnAt(0);
        if (n != 0) throw _err(BackupSnapshotErrorCode.corruptContents);
      }
      if (!_sameMap(_tableCounts(src), manifest.tables) ||
          !_sameMap(_settingsOf(src), settings)) {
        throw _err(BackupSnapshotErrorCode.corruptContents);
      }
    });
    final dst = _open(stage, dbKey, BackupSnapshotErrorCode.io);
    try {
      _guard(
        BackupSnapshotErrorCode.io,
        () => dst.execute('PRAGMA journal_mode = DELETE'),
      );
      await _guardAsync(
        BackupSnapshotErrorCode.io,
        () => src.backup(dst, nPage: -1).drain<void>(),
      );
    } finally {
      dst.close();
    }
  } finally {
    src.close();
  }
  await _guardAsync(BackupSnapshotErrorCode.io, () => snap.delete());

  // Migrate (if older) and compare the shape with the current schema:
  // the app's own steps, no migration guard (its copy files belong to the
  // live directory), validateSchema on.
  final db = AppDatabase(
    openEncryptedExecutor(stage, dbKey, inBackground: false),
    validateSchema: true,
  );
  try {
    await db.doWhenOpened((_) {});
  } on Object {
    throw _err(BackupSnapshotErrorCode.corruptContents);
  } finally {
    try {
      await db.close();
    } on Object {
      // The open error matters.
    }
  }

  final check = _open(stage, dbKey, BackupSnapshotErrorCode.io);
  try {
    _guard(BackupSnapshotErrorCode.corruptContents, () {
      if (_userVersion(check) != appSchemaVersion ||
          !_integrityOk(check) ||
          !_foreignKeysOk(check)) {
        throw _err(BackupSnapshotErrorCode.corruptContents);
      }
    });
  } finally {
    check.close();
  }
}

/// Design note §4 step 6: the live device's device tables replace the
/// staged ones (one read transaction on live, one write transaction on
/// [stage]); the restored key slot and the restore follow-ups are written.
/// Reads the live database only.
Future<void> carryDeviceState({
  required File live,
  required File stage,
  required DbKeyMaterial dbKey,
  required Uint8List slotCbor,
  required String slotStateKey,
  required int nowMs,
}) async {
  final src = _open(live, dbKey, BackupSnapshotErrorCode.liveUnavailable);
  final Map<String, (List<String>, List<List<Object?>>)> rows;
  final int livePageSize;
  try {
    rows = _guard(BackupSnapshotErrorCode.liveUnavailable, () {
      if (_userVersion(src) != appSchemaVersion) {
        throw _err(BackupSnapshotErrorCode.liveUnavailable);
      }
      src.execute('BEGIN');
      try {
        return {
          for (final t in deviceTables)
            t: (
              [
                for (final c in src.select('PRAGMA table_info("$t")'))
                  c['name'] as String,
              ],
              [for (final r in src.select('SELECT * FROM "$t"')) r.values],
            ),
        };
      } finally {
        src.execute('COMMIT');
      }
    });
    livePageSize = _guard(
      BackupSnapshotErrorCode.liveUnavailable,
      () => _pageSize(src),
    );
  } finally {
    src.close();
  }

  final dst = _open(stage, dbKey, BackupSnapshotErrorCode.io);
  try {
    _guard(BackupSnapshotErrorCode.io, () {
      if (_pageSize(dst) != livePageSize ||
          _userVersion(dst) != appSchemaVersion) {
        throw _err(BackupSnapshotErrorCode.corruptContents);
      }
      dst.execute('BEGIN IMMEDIATE');
      try {
        for (final t in deviceTables.reversed) {
          dst.execute('DELETE FROM "$t"');
        }
        for (final t in deviceTables) {
          final (cols, values) = rows[t]!;
          if (values.isEmpty) continue;
          final names = cols.map((c) => '"$c"').join(', ');
          final marks = List.filled(cols.length, '?').join(', ');
          final stmt = dst.prepare('INSERT INTO "$t" ($names) VALUES ($marks)');
          try {
            for (final v in values) {
              stmt.execute(v);
            }
          } finally {
            stmt.close();
          }
        }
        dst.execute(
          'INSERT OR REPLACE INTO secure_state ("key", value, updated_at) '
          'VALUES (?, ?, ?)',
          [slotStateKey, slotCbor, nowMs],
        );
        for (final k in [restoreRegrantDueKey, restoreCatalogResyncDueKey]) {
          dst.execute(
            'INSERT OR REPLACE INTO db_meta ("key", value) VALUES (?, ?)',
            [k, '1'],
          );
        }
        if (!_foreignKeysOk(dst)) {
          throw _err(BackupSnapshotErrorCode.corruptContents);
        }
        dst.execute('COMMIT');
      } on Object {
        if (!dst.autocommit) dst.execute('ROLLBACK');
        rethrow;
      }
      dst.select('PRAGMA wal_checkpoint(TRUNCATE)');
      dst.execute('PRAGMA journal_mode = DELETE');
    });
  } finally {
    dst.close();
  }
}

/// How long the swap may wait for the live database's write lock (other
/// connections) before it gives up and rolls back.
const Duration swapTimeout = Duration(seconds: 60);

/// Design note §4 step 7: replaces the live database's content with
/// [stage]'s through the SQLite backup API on a connection to [live]. All
/// pages are written in one write transaction on the live file: until its
/// commit, a crash, error, timeout or cancel leaves the old database as it
/// was (SQLite rolls the transaction back, also on the next open).
///
/// [pagesPerStep] and [onStep] are test seams (the app copies in one step);
/// an [onStep] that throws aborts and rolls back like a failure.
Future<void> swapIntoLive({
  required File stage,
  required File live,
  required DbKeyMaterial dbKey,
  int pagesPerStep = -1,
  Duration timeout = swapTimeout,
  void Function()? onStep,
}) async {
  final src = _open(stage, dbKey, BackupSnapshotErrorCode.io);
  try {
    final dst = _open(live, dbKey, BackupSnapshotErrorCode.liveUnavailable);
    try {
      _guard(BackupSnapshotErrorCode.liveUnavailable, () {
        if (_userVersion(dst) != appSchemaVersion ||
            _userVersion(src) != appSchemaVersion ||
            _pageSize(dst) != _pageSize(src)) {
          throw _err(BackupSnapshotErrorCode.liveUnavailable);
        }
      });
      await _guardAsync(BackupSnapshotErrorCode.swapFailed, () async {
        await for (final _
            in src.backup(dst, nPage: pagesPerStep).timeout(timeout)) {
          onStep?.call();
        }
      });
      _guard(BackupSnapshotErrorCode.swapFailed, () {
        if (_userVersion(dst) != appSchemaVersion) {
          throw _err(BackupSnapshotErrorCode.swapFailed);
        }
        dst.select('PRAGMA wal_checkpoint(PASSIVE)');
      });
    } finally {
      dst.close();
    }
  } finally {
    src.close();
  }
}

/// True when [file] starts with the plaintext SQLite magic (test and scan
/// helper; never true for a file written here).
bool startsWithPlaintextMagic(File file) {
  final raf = file.openSync();
  try {
    final head = raf.readSync(sqlitePlaintextMagic.length);
    if (head.length < sqlitePlaintextMagic.length) return false;
    for (var i = 0; i < head.length; i++) {
      if (head[i] != sqlitePlaintextMagic[i]) return false;
    }
    return true;
  } finally {
    raf.closeSync();
  }
}
