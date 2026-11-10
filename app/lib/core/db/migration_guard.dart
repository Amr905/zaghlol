// T-016: the pre-migration safety net that runs inside drift's `setup`
// (design note §6). After the keyed open sequence it reads
// `PRAGMA user_version` and, before drift runs any migration step, either
// refuses (too new / not allowed here) or makes a byte copy of the main file.
//
// The copy is a plain file copy after `PRAGMA wal_checkpoint(TRUNCATE)`: it is
// encrypted with the same key and salt by construction (database-schema §4.3;
// `VACUUM INTO` can't run inside drift's migration transaction and its key
// semantics under sqlite3mc are unproven). Nothing here logs; failures are
// code-only [DbOpenException]s.

import 'dart:io';

import 'db_errors.dart';
import 'db_file_set.dart';

/// Copies [source] into [part] (created or truncated) and flushes it to disk.
/// Must be a top-level or static function: the guard is sent to drift's
/// background isolate.
typedef MigrationCopier = void Function(File source, File part);

/// The app's copier: a chunked byte copy with a final flush.
void copyFileForMigration(File source, File part) {
  final input = source.openSync();
  try {
    final output = part.openSync(mode: FileMode.write);
    try {
      final buffer = List<int>.filled(1 << 20, 0);
      while (true) {
        final n = input.readIntoSync(buffer);
        if (n <= 0) break;
        output.writeFromSync(buffer, 0, n);
      }
      output.flushSync();
    } finally {
      output.closeSync();
    }
  } finally {
    input.closeSync();
  }
}

/// What the open may do about an older or newer schema. Sendable to drift's
/// background isolate (ints, a bool and a top-level function).
final class MigrationGuard {
  const MigrationGuard({
    required this.targetVersion,
    required this.allowMigration,
    this.copier = copyFileForMigration,
  });

  /// The schema version the opening code expects.
  final int targetVersion;

  /// False for the headless engine (T-008): it never migrates, so two
  /// engines can't race a schema change. The spool keeps the entry
  /// (ack-after-commit) and the UI engine migrates.
  final bool allowMigration;

  final MigrationCopier copier;

  /// Runs in `setup` after the open sequence. [userVersion] reads
  /// `PRAGMA user_version`; [checkpoint] runs `wal_checkpoint(TRUNCATE)` and
  /// returns false when it could not complete.
  ///
  /// - `v == 0` (new file) or `v == target`: nothing to do.
  /// - `v > target`: [DbOpenException.schemaTooNew], file untouched (EC-26).
  /// - `v < target` and not [allowMigration]:
  ///   [DbOpenException.migrationPending].
  /// - `v < target`: checkpoint, copy `zaghlol.db` → `.migrate.part`, flush,
  ///   rename to `.migrate.tmp`. Any failure deletes the `.part` and is
  ///   [DbOpenException.migrateCopyFailed]; nothing was migrated.
  void check(int Function() userVersion, bool Function() checkpoint, File db) {
    final v = userVersion();
    if (v == 0 || v == targetVersion) return;
    if (v > targetVersion) {
      throw DbOpenException(DbOpenException.schemaTooNew);
    }
    if (!allowMigration) {
      throw DbOpenException(DbOpenException.migrationPending);
    }
    final files = DbFileSet(db.parent);
    final part = files.migratePart;
    try {
      if (!checkpoint()) {
        throw DbOpenException(DbOpenException.migrateCopyFailed);
      }
      copier(db, part);
      part.renameSync(files.migrateTmp.path);
    } on Object {
      try {
        if (part.existsSync()) part.deleteSync();
      } on FileSystemException {
        // Step 1 of the next open deletes any `.part`.
      }
      throw DbOpenException(DbOpenException.migrateCopyFailed);
    }
  }
}
