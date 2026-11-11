// T-016 §6: a synthetic, test-only schema one version past the app's, to
// exercise the migration safety net (pre-migration copy, restore on failure)
// on top of the real latest schema. One trivial data step that can be made
// to fail. T-017: renamed from FakeV2Database (the app is at v2 now); an
// older file first runs the app's real steps up to [appSchemaVersion].

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';

enum FakeNextMode {
  /// The step succeeds.
  ok,

  /// The step writes, then throws.
  throwInStep,

  /// The step leaves a foreign-key violation (caught by the FK check).
  fkViolation,
}

/// Schema "next" = the app's current schema plus one `db_meta` row written
/// by the step.
class FakeNextDatabase extends AppDatabase {
  FakeNextDatabase(
    super.e, {
    super.restoreNoticeDue,
    this.mode = FakeNextMode.ok,
    this.onStep,
  }) : super(validateSchema: false);

  static const int version = appSchemaVersion + 1;

  final FakeNextMode mode;

  /// Runs at the start of the step (on the client isolate), while the
  /// pre-migration copy exists.
  final void Function()? onStep;

  int steps = 0;

  @override
  int get schemaVersion => version;

  @override
  Future<void> upgradeSteps(Migrator m, int from, int to) async {
    if (from < 1 || from >= version || to != version) {
      throw StateError('FAKE_NEXT_UNEXPECTED_PATH');
    }
    if (from < appSchemaVersion) {
      await super.upgradeSteps(m, from, appSchemaVersion);
    }
    steps++;
    onStep?.call();
    await customStatement(
      "INSERT OR REPLACE INTO db_meta (key, value) VALUES ('fake_next', '1')",
    );
    switch (mode) {
      case FakeNextMode.ok:
        return;
      case FakeNextMode.throwInStep:
        throw StateError('FAKE_NEXT_STEP_FAILED');
      case FakeNextMode.fkViolation:
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
DatabaseFactory<FakeNextDatabase> fakeNextFactory({
  FakeNextMode mode = FakeNextMode.ok,
  void Function()? onStep,
  List<FakeNextDatabase>? opened,
}) => (executor, {required restoreNoticeDue}) {
  final db = FakeNextDatabase(
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
