// T-015: the keyed open sequence for the encrypted database (ADR-002, T-007
// "Open sequence"; design note §5 and §7). T-016's AppDatabase opens through
// [openEncryptedExecutor]; nothing else may issue `PRAGMA key` / `rekey`.
//
// Key hygiene (T-007 security I-2):
// - The hex key String is built only inside drift's `setup` closure and passed
//   straight to the key statement. A failing key statement is rethrown as a
//   code-only [DbOpenException]: a raw SqliteException carries the statement
//   (and so the key) in `causingStatement` / `toString()`.
// - drift `logStatements` is off in every flavor ([driftLogStatements]).

import 'dart:io';

import 'package:drift/drift.dart' show DriftWrappedException, QueryExecutor;
import 'package:drift/native.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' as sql;

import 'db_errors.dart';
import 'key_bootstrap.dart';
import 'migration_guard.dart';

export 'db_errors.dart';

/// drift statement logging. Must stay false in every flavor: logged
/// statements could include `PRAGMA key` or user data.
const bool driftLogStatements = false;

/// SQLITE_NOTADB: "file is not a database" (wrong key, or a corrupt page 1).
const int sqliteNotADb = 26;

/// Finds a [DbOpenException] in [error] or in drift's wrappers (foreground
/// `DriftWrappedException.cause`, background `DriftRemoteException`).
DbOpenException? dbOpenExceptionOf(Object error) {
  Object? current = error;
  for (var depth = 0; depth < 5 && current != null; depth++) {
    switch (current) {
      case final DbOpenException e:
        return e;
      case final DriftRemoteException e:
        current = e.remoteCause;
      case final DriftWrappedException e:
        current = e.cause;
      case final String s when DbOpenException.codes.contains(s):
        // A serialized remote error keeps only toString(), which is the code.
        return DbOpenException(s);
      default:
        return null;
    }
  }
  return null;
}

/// Opens [file] with [key] the way the app does: the keyed open sequence in
/// drift's `setup`, statement logging off. With [inBackground] (the app's
/// default) the database runs in drift's background isolate; the setup
/// closure, and with it a copy of the key bytes, is sent there (accepted,
/// design note §5).
///
/// T-016: [guard] (the app's open) runs the pre-migration check and copy in
/// `setup`, after the open sequence and [applyAppPragmas] (design note §6).
///
/// The caller zeroizes [key] right after the first successful statement.
QueryExecutor openEncryptedExecutor(
  File file,
  DbKeyMaterial key, {
  bool inBackground = true,
  MigrationGuard? guard,
}) {
  final setup = _setupFor(key, file.path, guard);
  if (inBackground) {
    return NativeDatabase.createInBackground(
      file,
      logStatements: driftLogStatements,
      setup: setup,
    );
  }
  return NativeDatabase(file, logStatements: driftLogStatements, setup: setup);
}

// Built in its own function so the closure captures only the key, the path
// string and the (sendable) guard.
void Function(sql.Database) _setupFor(
  DbKeyMaterial key,
  String path,
  MigrationGuard? guard,
) => (raw) {
  // First: two engines share the file, and the sequence below reads it
  // (journal_mode, verify). Without a timeout a concurrent close or
  // checkpoint fails the open at once with SQLITE_BUSY.
  applyBusyTimeout(raw);
  applyEncryptedOpenSequence(raw, key);
  applyAppPragmas(raw);
  if (guard != null) {
    guard.check(
      () => _userVersion(raw),
      () => _checkpointTruncate(raw),
      File(path),
    );
  }
};

/// T-016 §5: `busy_timeout = 5000`, before anything reads the file (a
/// connection setting; it reads nothing, so it may precede the key).
void applyBusyTimeout(sql.Database raw) {
  _exec(raw, 'PRAGMA busy_timeout = 5000');
}

/// T-016 §5: the connection PRAGMAs after the keyed sequence.
/// `secure_delete = FAST` zeroes freed content where it costs no extra I/O
/// (defence in depth for purged raw SMS; the file is encrypted anyway);
/// `cache_size` 8 MiB (ADR-002 finding 4). `foreign_keys` is set in drift's
/// `beforeOpen` (a no-op inside a transaction, so never here).
void applyAppPragmas(sql.Database raw) {
  _exec(raw, 'PRAGMA secure_delete = FAST');
  _exec(raw, 'PRAGMA cache_size = -8192');
}

int _userVersion(sql.Database raw) {
  final rows = _select(raw, 'PRAGMA user_version');
  final v = rows.isEmpty ? null : rows.first.first;
  if (v is! int) throw DbOpenException(DbOpenException.openFailed);
  return v;
}

/// True when the WAL was fully checkpointed and truncated (busy == 0).
bool _checkpointTruncate(sql.Database raw) {
  final rows = _select(raw, 'PRAGMA wal_checkpoint(TRUNCATE)');
  return rows.isNotEmpty && rows.first.first == 0;
}

/// The open sequence (T-007): cipher and legacy PRAGMAs, the raw key, then
/// temp_store, WAL and synchronous, then verification. Everything before the
/// key is a PRAGMA, because any SELECT reads the file.
void applyEncryptedOpenSequence(sql.Database raw, DbKeyMaterial key) {
  _exec(raw, "PRAGMA cipher = 'sqlcipher'");
  _exec(raw, 'PRAGMA legacy = 4');
  _execKey(raw, key);
  _exec(raw, 'PRAGMA temp_store = 2');
  _exec(raw, 'PRAGMA journal_mode = WAL');
  _exec(raw, 'PRAGMA synchronous = NORMAL');
  verifyEncrypted(raw);
}

/// The verification half: page 1 decrypts, the cipher is sqlcipher and the
/// main database has a cipher salt.
void verifyEncrypted(sql.Database raw) {
  // Forces decryption of page 1.
  _select(raw, 'SELECT count(*) FROM sqlite_master');
  final cipher = _select(raw, 'PRAGMA cipher');
  if (cipher.isEmpty || cipher.first.first != 'sqlcipher') {
    throw DbOpenException(DbOpenException.notEncrypted);
  }
  final salt = _select(raw, "SELECT sqlite3mc_codec_data('cipher_salt')");
  if (salt.isEmpty || salt.first.first == null) {
    throw DbOpenException(DbOpenException.notEncrypted);
  }
}

/// The only place a key statement runs. The SqliteException (which holds the
/// statement) is dropped; only its result code survives.
void _execKey(sql.Database raw, DbKeyMaterial key) {
  try {
    raw.execute('PRAGMA key = "x\'${key.toRawKeyHex()}\'"');
  } on sql.SqliteException catch (e) {
    throw DbOpenException(
      DbOpenException.keyPragmaFailed,
      sqliteCode: e.resultCode,
    );
  }
}

void _exec(sql.Database raw, String statement) {
  try {
    raw.execute(statement);
  } on sql.SqliteException catch (e) {
    throw _failure(e);
  }
}

List<List<Object?>> _select(sql.Database raw, String query) {
  try {
    return raw.select(query).rows;
  } on sql.SqliteException catch (e) {
    throw _failure(e);
  }
}

/// SQLITE_NOTADB can only come from reading page 1 (the statements before
/// the key never read the file), so it means "key rejected". Every other code
/// is a plain open failure.
DbOpenException _failure(sql.SqliteException e) => e.resultCode == sqliteNotADb
    ? DbOpenException(DbOpenException.keyRejected, sqliteCode: sqliteNotADb)
    : DbOpenException(DbOpenException.openFailed, sqliteCode: e.resultCode);
