// T-017: maps a failed write to a code-only [DbWriteException] (design note
// §6, §7). A raw `SqliteException` carries the statement and its bound
// parameters (merchant names, message bodies, amounts), so it never leaves
// a DAO: every DAO write runs through [guardWrite]. Nothing here logs.

import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../db_errors.dart';

// SQLite extended result codes (sqlite.org/rescode.html).
const int _constraint = 19;
const int _constraintCheck = 275;
const int _constraintForeignKey = 787;
const int _constraintNotNull = 1299;
const int _constraintPrimaryKey = 1555;
const int _constraintTrigger = 1811;
const int _constraintUnique = 2067;

/// Runs [write] and turns any database error into a [DbWriteException].
/// Other errors (programming errors, [DbWriteException] itself) pass through
/// unchanged.
Future<T> guardWrite<T>(Future<T> Function() write) async {
  try {
    return await write();
  } on DbWriteException {
    rethrow;
  } on Object catch (e) {
    final mapped = writeExceptionOf(e);
    if (mapped == null) rethrow;
    throw mapped;
  }
}

/// The [DbWriteException] for [error] (also inside drift's foreground and
/// background wrappers), or null when it is not a database error.
DbWriteException? writeExceptionOf(Object error) {
  Object? current = error;
  for (var depth = 0; depth < 5 && current != null; depth++) {
    switch (current) {
      case final SqliteException e:
        return _fromSqlite(e);
      case final DriftRemoteException e:
        current = e.remoteCause;
      case final DriftWrappedException e:
        current = e.cause;
      default:
        return null;
    }
  }
  return null;
}

DbWriteException _fromSqlite(SqliteException e) {
  final extended = e.extendedResultCode;
  final code = switch (extended) {
    _constraintCheck => DbWriteException.constraintCheck,
    _constraintUnique => DbWriteException.constraintUnique,
    _constraintPrimaryKey => DbWriteException.constraintPrimaryKey,
    _constraintForeignKey => DbWriteException.constraintForeignKey,
    _constraintNotNull => DbWriteException.constraintNotNull,
    // RAISE(ABORT, msg): the message is the trigger's fixed code. Only a
    // known code is passed on; anything else is generic.
    _constraintTrigger when DbWriteException.triggerCodes.contains(e.message) =>
      e.message,
    _constraintTrigger => DbWriteException.constraintTrigger,
    _ when e.resultCode == _constraint => DbWriteException.constraint,
    _ => DbWriteException.writeFailed,
  };
  return DbWriteException(code, sqliteCode: extended);
}
