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
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import 'key_bootstrap.dart';

/// drift statement logging. Must stay false in every flavor: logged
/// statements could include `PRAGMA key` or user data.
const bool driftLogStatements = false;

/// SQLITE_NOTADB: "file is not a database" (wrong key, or a corrupt page 1).
const int sqliteNotADb = 26;

/// A failed open. Carries a constant code and the SQLite result code only.
///
/// Codes: `DB_KEY_PRAGMA_FAILED` (the key statement failed),
/// `DB_KEY_REJECTED` (SQLITE_NOTADB on the first page read: report it with
/// `KeyBootstrap.reportRejected`), `DB_NOT_ENCRYPTED` (the file opened but is
/// not SQLCipher-encrypted), `DB_OPEN_FAILED` (any other SQLite error during
/// the open sequence; transient, never a reason to wipe).
final class DbOpenException extends SafeException {
  DbOpenException(super.code, {this.sqliteCode});

  static const String keyPragmaFailed = 'DB_KEY_PRAGMA_FAILED';
  static const String keyRejected = 'DB_KEY_REJECTED';
  static const String notEncrypted = 'DB_NOT_ENCRYPTED';
  static const String openFailed = 'DB_OPEN_FAILED';

  static const Set<String> codes = {
    keyPragmaFailed,
    keyRejected,
    notEncrypted,
    openFailed,
  };

  final int? sqliteCode;

  /// True only for SQLITE_NOTADB on the first page read.
  bool get isKeyRejected => code == keyRejected;
}

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
/// The caller zeroizes [key] right after the first successful statement.
QueryExecutor openEncryptedExecutor(
  File file,
  DbKeyMaterial key, {
  bool inBackground = true,
}) {
  final setup = _setupFor(key);
  if (inBackground) {
    return NativeDatabase.createInBackground(
      file,
      logStatements: driftLogStatements,
      setup: setup,
    );
  }
  return NativeDatabase(file, logStatements: driftLogStatements, setup: setup);
}

// Built in its own function so the closure captures only the key.
void Function(sql.Database) _setupFor(DbKeyMaterial key) =>
    (raw) => applyEncryptedOpenSequence(raw, key);

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
