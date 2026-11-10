// T-016 §4: the open sequence of zaghlol.db. Pure orchestration over injected
// dependencies (file set, key bootstrap, executor, database factory, wipe
// steps). Returns a [DbOpenResult]; never throws to the UI and never logs.
//
// 1. File recovery (no key needed): delete a leftover `.migrate.part`; a
//    `.migrate.tmp` means a migration was not confirmed, so roll back to it.
// 2. KeyBootstrap.obtain():
//    - KeyReady: open. SQLITE_NOTADB → reportRejected (KeyInvalidated → wipe;
//      KeyReady → one retry with the new key). Any other open error is
//      DB_UNAVAILABLE and never a wipe.
//    - KeyCreated: lease.ensureValid(), then create (db_meta restore notice
//      in the create transaction).
//    - KeyInvalidated: wipe under the lease (ensureValid before each step),
//      recreateAfterWipe, create.
//    - KeyUnavailable → DB_UNAVAILABLE; KeyStoreFailed → DB_STORE_FAILED.
// 3. A failed migration restores the pre-migration copy.

import 'dart:io';

import 'package:drift/drift.dart' show GeneratedDatabase, QueryExecutor;
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import 'app_database.dart';
import 'db_file_set.dart';
import 'encrypted_open.dart';
import 'key_bootstrap.dart';
import 'migration_guard.dart';
import 'orphan_wipe.dart';

/// Why the database could not be opened. A closed set: the startup gate
/// (not T-016) maps every value to a screen through [dbGateStateFor].
enum DbOpenFailureCode {
  /// Transient: key not readable now, SQLite busy/IO error, lease lapsed.
  /// Retry; never a wipe.
  unavailable('DB_UNAVAILABLE'),

  /// No key could be generated or stored; no database was created.
  storeFailed('DB_STORE_FAILED'),

  /// A migration failed; see [DbOpenFailed.restored].
  migrationFailed('DB_MIGRATION_FAILED'),

  /// The orphan wipe left files behind; nothing was recreated.
  wipeIncomplete('DB_WIPE_INCOMPLETE'),

  /// An older schema and this engine may not migrate (headless engine).
  migrationPending('DB_MIGRATION_PENDING'),

  /// The file is from a newer app version (EC-26); untouched.
  schemaTooNew('DB_SCHEMA_TOO_NEW'),

  /// The pre-migration copy could not be made (e.g. disk full); nothing was
  /// migrated.
  migrateCopyFailed('DB_MIGRATE_COPY_FAILED');

  const DbOpenFailureCode(this.code);

  final String code;
}

/// What the startup gate shows for a failure (error-handling §1).
enum DbGateState {
  /// Retry later (foreground gate retries; background keeps the spool).
  retry,

  /// Key storage broken: the "can't open your data" screen.
  keyStoreFailed,

  /// «التحديث ماكملش» with retry.
  updateFailed,

  /// The app is older than the data: ask for an app update.
  appUpdateRequired,

  /// Headless engine: leave the work to the UI engine.
  deferToForeground,

  /// The orphan wipe did not finish: retry (it resumes).
  wipeIncomplete,
}

/// Total mapping of every failure code to a gate state.
DbGateState dbGateStateFor(DbOpenFailureCode code) => switch (code) {
  DbOpenFailureCode.unavailable => DbGateState.retry,
  DbOpenFailureCode.storeFailed => DbGateState.keyStoreFailed,
  DbOpenFailureCode.migrationFailed => DbGateState.updateFailed,
  DbOpenFailureCode.migrateCopyFailed => DbGateState.updateFailed,
  DbOpenFailureCode.wipeIncomplete => DbGateState.wipeIncomplete,
  DbOpenFailureCode.migrationPending => DbGateState.deferToForeground,
  DbOpenFailureCode.schemaTooNew => DbGateState.appUpdateRequired,
};

/// The result of [openAppDatabase]. Never carries a path, SQL or key.
sealed class DbOpenResult<D> {
  const DbOpenResult();

  /// FU-050 diag code (emitted by T-021's logger; nothing is logged today).
  String get diagCode;

  /// The only diag fields: `{code, fromVersion, toVersion, platform}`.
  Map<String, Object?> diagFields(String platform);
}

final class DbOpened<D> extends DbOpenResult<D> {
  const DbOpened(
    this.db, {
    required this.created,
    required this.wipedOrphan,
    this.migratedFrom,
    required this.toVersion,
  });

  final D db;

  /// A new database file was created by this open.
  final bool created;

  /// An orphaned database was wiped first (the restore notice is due).
  final bool wipedOrphan;

  /// The version a migration started from (null: no migration ran).
  final int? migratedFrom;

  final int toVersion;

  @override
  String get diagCode => wipedOrphan
      ? 'DB_ORPHAN_WIPED'
      : migratedFrom != null
      ? 'DB_MIGRATED'
      : 'DB_OPEN_OK';

  @override
  Map<String, Object?> diagFields(String platform) => {
    'code': diagCode,
    'fromVersion': migratedFrom,
    'toVersion': toVersion,
    'platform': platform,
  };

  @override
  String toString() => 'DbOpened(created: $created, wiped: $wipedOrphan)';
}

final class DbOpenFailed<D> extends DbOpenResult<D> {
  const DbOpenFailed(
    this.code, {
    this.leaseLapsed = false,
    this.restored,
    this.fromVersion,
    required this.toVersion,
  });

  final DbOpenFailureCode code;

  /// [DbOpenFailureCode.unavailable] because the bootstrap lease lapsed
  /// before a create or wipe step (nothing was touched).
  final bool leaseLapsed;

  /// For [DbOpenFailureCode.migrationFailed]: true when the pre-migration
  /// copy was restored; false when restoring failed (the copy is kept and the
  /// next open retries the rollback).
  final bool? restored;

  final int? fromVersion;
  final int toVersion;

  @override
  String get diagCode => code == DbOpenFailureCode.migrationFailed
      ? 'DB_MIGRATION_FAILED'
      : 'DB_OPEN_FAILED';

  @override
  Map<String, Object?> diagFields(String platform) => {
    'code': code.code,
    'fromVersion': fromVersion,
    'toVersion': toVersion,
    'platform': platform,
  };

  @override
  String toString() => 'DbOpenFailed(${code.code})';
}

/// [DbOpenFailed] as an exception for `appDatabaseProvider`.
final class DbOpenFailure extends SafeException {
  DbOpenFailure(this.failure) : super(failure.code);

  final DbOpenFailureCode failure;
}

/// Builds the database over [executor].
typedef DatabaseFactory<D extends GeneratedDatabase> = D Function(
  QueryExecutor executor, {
  required bool restoreNoticeDue,
});

/// Builds the encrypted executor for the main file.
typedef DbExecutorFactory = QueryExecutor Function(
  File file,
  DbKeyMaterial key,
  MigrationGuard guard,
);

/// The app's executor: drift's background isolate, the keyed open sequence,
/// the PRAGMAs and the migration guard.
QueryExecutor defaultDbExecutor(
  File file,
  DbKeyMaterial key,
  MigrationGuard guard,
) => openEncryptedExecutor(file, key, guard: guard);

AppDatabase _appDatabase(
  QueryExecutor executor, {
  required bool restoreNoticeDue,
}) => AppDatabase(executor, restoreNoticeDue: restoreNoticeDue);

/// Opens zaghlol.db in [files] (design note §4). [allowMigration] is false
/// for the headless engine.
Future<DbOpenResult<AppDatabase>> openAppDatabase({
  required DbFileSet files,
  required KeyBootstrap bootstrap,
  required List<OrphanWipeStep> wipeSteps,
  bool allowMigration = true,
  DbExecutorFactory executor = defaultDbExecutor,
  MigrationCopier copier = copyFileForMigration,
}) => openDatabaseWith<AppDatabase>(
  files: files,
  bootstrap: bootstrap,
  wipeSteps: wipeSteps,
  database: _appDatabase,
  schemaVersion: appSchemaVersion,
  allowMigration: allowMigration,
  executor: executor,
  copier: copier,
);

/// [openAppDatabase] for any database class (tests use a v2 class).
Future<DbOpenResult<D>> openDatabaseWith<D extends GeneratedDatabase>({
  required DbFileSet files,
  required KeyBootstrap bootstrap,
  required List<OrphanWipeStep> wipeSteps,
  required DatabaseFactory<D> database,
  required int schemaVersion,
  bool allowMigration = true,
  DbExecutorFactory executor = defaultDbExecutor,
  MigrationCopier copier = copyFileForMigration,
}) async {
  final opener = _Opener<D>(
    files: files,
    bootstrap: bootstrap,
    wipeSteps: wipeSteps,
    database: database,
    guard: MigrationGuard(
      targetVersion: schemaVersion,
      allowMigration: allowMigration,
      copier: copier,
    ),
    executor: executor,
  );
  try {
    return await opener.run();
  } on Object {
    // Never throws to the UI. Every expected failure is mapped inside; an
    // unexpected one is transient by policy (never a wipe).
    return opener.failed(DbOpenFailureCode.unavailable);
  }
}

final class _Opener<D extends GeneratedDatabase> {
  _Opener({
    required this.files,
    required this.bootstrap,
    required this.wipeSteps,
    required this.database,
    required this.guard,
    required this.executor,
  });

  final DbFileSet files;
  final KeyBootstrap bootstrap;
  final List<OrphanWipeStep> wipeSteps;
  final DatabaseFactory<D> database;
  final MigrationGuard guard;
  final DbExecutorFactory executor;

  int? _fromVersion;

  DbOpenFailed<D> failed(
    DbOpenFailureCode code, {
    bool leaseLapsed = false,
    bool? restored,
  }) => DbOpenFailed<D>(
    code,
    leaseLapsed: leaseLapsed,
    restored: restored,
    fromVersion: _fromVersion,
    toVersion: guard.targetVersion,
  );

  Future<DbOpenResult<D>> run() async {
    try {
      await files.directory.create(recursive: true);
    } on FileSystemException {
      return failed(DbOpenFailureCode.unavailable);
    }
    final recovery = await _recoverFiles();
    if (recovery != null) return recovery;

    final outcome = await bootstrap.obtain();
    if (outcome is KeyReady && !await _mainExists()) {
      // Leftovers without a main file (e.g. a WAL): no database to protect.
      // Delete them and ask again, which now takes the rotate path.
      outcome.key.zeroize();
      try {
        for (final f in files.wipeOrder) {
          await DeleteFileStep('leftover', f).run();
        }
      } on FileSystemException {
        return failed(DbOpenFailureCode.unavailable);
      }
      final again = await bootstrap.obtain();
      if (again is KeyReady && !await _mainExists()) {
        again.key.zeroize();
        return failed(DbOpenFailureCode.unavailable);
      }
      return _handle(again);
    }
    return _handle(outcome);
  }

  Future<bool> _mainExists() async {
    try {
      return await files.mainFile.exists();
    } on FileSystemException {
      return true; // can't tell: never treat as absent
    }
  }

  Future<DbOpenResult<D>> _handle(KeyBootstrapOutcome outcome) async {
    switch (outcome) {
      case KeyReady(:final key):
        try {
          return await _openExisting(key, retried: false);
        } finally {
          key.zeroize();
        }
      case KeyCreated():
        return _create(outcome, wipedOrphan: false);
      case KeyInvalidated():
        return _wipeAndCreate(outcome);
      case KeyUnavailable():
        return failed(DbOpenFailureCode.unavailable);
      case KeyStoreFailed():
        return failed(DbOpenFailureCode.storeFailed);
    }
  }

  /// Step 1: no key needed. Only an engine that may migrate rolls back; a
  /// headless engine that finds an unconfirmed migration defers to the UI
  /// engine (it could be migrating right now).
  Future<DbOpenResult<D>?> _recoverFiles() async {
    try {
      for (final f in [
        files.migratePart,
        for (final s in dbCompanionSuffixes.skip(1))
          File('${files.migratePart.path}$s'),
      ]) {
        await DeleteFileStep('part', f).run();
      }
      if (!await files.migrateTmp.exists()) return null;
    } on FileSystemException {
      return failed(DbOpenFailureCode.unavailable);
    }
    if (!guard.allowMigration) {
      return failed(DbOpenFailureCode.migrationPending);
    }
    if (await _restoreCopy()) return null;
    return failed(DbOpenFailureCode.migrationFailed, restored: false);
  }

  /// Replaces the main file with `.migrate.tmp`: delete the main file's
  /// `-wal`/`-shm`/`-journal` (they belong to the failed migration), then
  /// rename. False when that failed; the copy is kept for the next open.
  Future<bool> _restoreCopy() async {
    try {
      for (final f in files.mainCompanions) {
        await DeleteFileStep('companion', f).run();
      }
      await files.migrateTmp.rename(files.mainFile.path);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<DbOpenResult<D>> _openExisting(
    DbKeyMaterial key, {
    required bool retried,
  }) async {
    try {
      final (db, from) = await _openAndConfirm(key, restoreNoticeDue: false);
      return DbOpened<D>(
        db,
        created: false,
        wipedOrphan: false,
        migratedFrom: from,
        toVersion: guard.targetVersion,
      );
    } on Object catch (e) {
      final open = dbOpenExceptionOf(e);
      if (open != null && open.isKeyRejected && !retried) {
        final again = await bootstrap.reportRejected(key);
        switch (again) {
          case KeyInvalidated():
            return _wipeAndCreate(again);
          case KeyReady(key: final next):
            try {
              return await _openExisting(next, retried: true);
            } finally {
              next.zeroize();
            }
          case KeyCreated():
            // Not produced by reportRejected; never create over a file.
            again.key.zeroize();
            await again.lease.release();
            return failed(DbOpenFailureCode.unavailable);
          case KeyUnavailable():
            return failed(DbOpenFailureCode.unavailable);
          case KeyStoreFailed():
            return failed(DbOpenFailureCode.storeFailed);
        }
      }
      return _afterFailure(e);
    }
  }

  Future<DbOpenResult<D>> _create(
    KeyCreated created, {
    required bool wipedOrphan,
  }) async {
    try {
      // S-2: prove the lease right before the first file is written.
      await created.lease.ensureValid();
      final (db, _) = await _openAndConfirm(
        created.key,
        restoreNoticeDue: created.restoreNoticeDue,
      );
      return DbOpened<D>(
        db,
        created: true,
        wipedOrphan: wipedOrphan,
        toVersion: guard.targetVersion,
      );
    } on Object catch (e) {
      return _afterFailure(e);
    } finally {
      created.key.zeroize();
      await created.lease.release();
    }
  }

  Future<DbOpenResult<D>> _wipeAndCreate(KeyInvalidated invalid) async {
    final lease = invalid.lease;
    try {
      for (final step in wipeSteps) {
        try {
          await lease.ensureValid();
        } on DbOpenException {
          return failed(DbOpenFailureCode.unavailable, leaseLapsed: true);
        }
        try {
          await step.run();
        } on FileSystemException {
          return failed(DbOpenFailureCode.wipeIncomplete);
        }
      }
      try {
        if (await files.anyExists()) {
          return failed(DbOpenFailureCode.wipeIncomplete);
        }
      } on FileSystemException {
        return failed(DbOpenFailureCode.wipeIncomplete);
      }
      // S-2: the key write is a creating step too.
      try {
        await lease.ensureValid();
      } on DbOpenException {
        return failed(DbOpenFailureCode.unavailable, leaseLapsed: true);
      }
      final next = await bootstrap.recreateAfterWipe(lease);
      switch (next) {
        case KeyCreated():
          return await _create(next, wipedOrphan: true);
        case KeyStoreFailed(reason: KeyStoreFailedReason.wipeIncomplete):
          return failed(DbOpenFailureCode.wipeIncomplete);
        case KeyStoreFailed():
          return failed(DbOpenFailureCode.storeFailed);
        case KeyReady(:final key):
          key.zeroize();
          return failed(DbOpenFailureCode.unavailable);
        case KeyInvalidated() || KeyUnavailable():
          return failed(DbOpenFailureCode.unavailable);
      }
    } finally {
      await lease.release();
    }
  }

  /// Opens (running setup, migrations and beforeOpen) and confirms a
  /// migration by deleting `.migrate.tmp`. On failure the database is closed
  /// before the error is rethrown.
  Future<(D, int?)> _openAndConfirm(
    DbKeyMaterial key, {
    required bool restoreNoticeDue,
  }) async {
    final db = database(
      executor(files.mainFile, key, guard),
      restoreNoticeDue: restoreNoticeDue,
    );
    try {
      await db.doWhenOpened((_) {});
    } on Object {
      _fromVersion = _upgradeFromOf(db);
      try {
        await db.close();
      } on Object {
        // Closing a failed open; the original error matters.
      }
      rethrow;
    }
    final from = _upgradeFromOf(db);
    _fromVersion = from;
    try {
      if (await files.migrateTmp.exists()) await files.migrateTmp.delete();
    } on FileSystemException {
      // Accepted (design note §6): the next open rolls back and re-migrates.
    }
    return (db, from);
  }

  static int? _upgradeFromOf(GeneratedDatabase db) =>
      db is AppDatabase ? db.attemptedUpgradeFrom : null;

  /// Maps an open failure. A copy made by this attempt is restored first
  /// (nothing was confirmed).
  Future<DbOpenResult<D>> _afterFailure(Object error) async {
    final open = dbOpenExceptionOf(error);
    bool? restored;
    try {
      if (await files.migrateTmp.exists()) restored = await _restoreCopy();
    } on FileSystemException {
      restored = false;
    }
    if (open == null) {
      // Failed after the open sequence: a migration step, the FK check, the
      // schema check, or the create itself.
      return restored == null
          ? failed(DbOpenFailureCode.unavailable)
          : failed(DbOpenFailureCode.migrationFailed, restored: restored);
    }
    if (restored == false) {
      return failed(DbOpenFailureCode.migrationFailed, restored: false);
    }
    return switch (open.code) {
      DbOpenException.schemaTooNew => failed(DbOpenFailureCode.schemaTooNew),
      DbOpenException.migrationPending => failed(
        DbOpenFailureCode.migrationPending,
      ),
      DbOpenException.migrateCopyFailed => failed(
        DbOpenFailureCode.migrateCopyFailed,
      ),
      DbOpenException.leaseLapsed => failed(
        DbOpenFailureCode.unavailable,
        leaseLapsed: true,
      ),
      _ => failed(DbOpenFailureCode.unavailable),
    };
  }
}
