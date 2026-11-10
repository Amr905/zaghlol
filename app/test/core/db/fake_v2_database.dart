// T-016 §6: a synthetic, test-only schema v2 of the app database, to exercise
// the migration safety net (pre-migration copy, restore on failure) before
// any real v2 exists. One trivial data step that can be made to fail.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';

enum FakeV2Mode {
  /// The step succeeds.
  ok,

  /// The step writes, then throws.
  throwInStep,

  /// The step leaves a foreign-key violation (caught by the FK check).
  fkViolation,
}

/// Schema v2 = v1 plus one `db_meta` row written by the step.
class FakeV2Database extends AppDatabase {
  FakeV2Database(
    super.e, {
    super.restoreNoticeDue,
    this.mode = FakeV2Mode.ok,
    this.onStep,
  }) : super(validateSchema: false);

  static const int version = 2;

  final FakeV2Mode mode;

  /// Runs at the start of the step (on the client isolate), while the
  /// pre-migration copy exists.
  final void Function()? onStep;

  int steps = 0;

  @override
  int get schemaVersion => version;

  @override
  Future<void> upgradeSteps(Migrator m, int from, int to) async {
    if (from != 1 || to != 2) {
      throw StateError('FAKE_V2_UNEXPECTED_PATH');
    }
    steps++;
    onStep?.call();
    await customStatement(
      "INSERT OR REPLACE INTO db_meta (key, value) VALUES ('fake_v2', '1')",
    );
    switch (mode) {
      case FakeV2Mode.ok:
        return;
      case FakeV2Mode.throwInStep:
        throw StateError('FAKE_V2_STEP_FAILED');
      case FakeV2Mode.fkViolation:
        await customStatement('CREATE TABLE fake_p (id INTEGER PRIMARY KEY)');
        await customStatement(
          'CREATE TABLE fake_c (id INTEGER PRIMARY KEY, '
          'p INTEGER NOT NULL REFERENCES fake_p (id))',
        );
        await customStatement('INSERT INTO fake_c (id, p) VALUES (1, 99)');
    }
  }
}

/// A database factory for [openDatabaseWith].
DatabaseFactory<FakeV2Database> fakeV2Factory({
  FakeV2Mode mode = FakeV2Mode.ok,
  void Function()? onStep,
  List<FakeV2Database>? opened,
}) => (executor, {required restoreNoticeDue}) {
  final db = FakeV2Database(
    executor,
    restoreNoticeDue: restoreNoticeDue,
    mode: mode,
    onStep: onStep,
  );
  opened?.add(db);
  return db;
};

/// A copier that fails like a full disk, after writing part of the copy.
/// Top-level so the guard can be sent to drift's background isolate.
void diskFullCopier(File source, File part) {
  part.writeAsBytesSync(const [1, 2, 3], flush: true);
  throw const FileSystemException('synthetic: no space left');
}
