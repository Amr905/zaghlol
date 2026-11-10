// T-016 §4 step 3: the orphan wipe (D-50, FR-SEC-05; T-165 F6). An existing
// database whose key can't be used is deleted, under the bootstrap lease,
// before a new key and database are created.
//
// The wipe is a list of steps. T-016 ships one step per database file, in
// [dbWipeOrder] (main file last), then the app temp directory. T-008 appends
// the spool and T-011 the Guard config. The opener proves the lease
// (BootstrapLease.ensureValid) before every step. No step ever names a
// secret: the only secret deleted is the database key, inside
// KeyBootstrap.recreateAfterWipe (never the iOS seat keys, D-62).

import 'dart:io';

import 'db_file_set.dart';

/// One idempotent part of the orphan wipe. [run] throws
/// [FileSystemException] when it could not delete everything it owns.
abstract interface class OrphanWipeStep {
  /// A constant name for tests and diag (never a path).
  String get id;

  Future<void> run();
}

/// Deletes one file (no-op when it is already gone).
final class DeleteFileStep implements OrphanWipeStep {
  DeleteFileStep(this.id, this._file);

  @override
  final String id;
  final File _file;

  @override
  Future<void> run() async {
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

/// Deletes everything inside a directory (the directory itself stays).
final class ClearDirectoryStep implements OrphanWipeStep {
  ClearDirectoryStep(this.id, this._directory);

  @override
  final String id;
  final Future<Directory> Function() _directory;

  @override
  Future<void> run() async {
    final dir = await _directory();
    try {
      await for (final entry in dir.list(followLinks: false)) {
        try {
          await entry.delete(recursive: true);
        } on PathNotFoundException {
          // Raced with another deleter.
        }
      }
    } on PathNotFoundException {
      // No directory, nothing to clear.
    }
  }
}

/// One step per database file, in [dbWipeOrder] (main file last).
List<OrphanWipeStep> dbFileWipeSteps(DbFileSet files) => [
  for (final name in dbWipeOrder)
    DeleteFileStep('db:$name', File('${files.directory.path}/$name')),
];
