// T-016 §4.4: Riverpod wiring for the encrypted database (ADR-001). Plain
// providers, kept alive. The startup gate (not T-016) overrides
// dbDirectoryProvider with `await resolveDbDirectory()`, watches
// appDatabaseProvider and maps a DbOpenFailure code to a screen
// (dbGateStateFor). Retry = `ref.invalidate(appDatabaseProvider)`.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';
import 'app_database_opener.dart';
import 'db_key_providers.dart';
import 'orphan_wipe.dart';

/// The app's temp directory, cleared by the orphan wipe. Overridden in tests.
final appTempDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
  name: 'appTempDirectoryProvider',
);

/// The orphan-wipe steps (T-016 §4 step 3): the database files in wipe order
/// (main file last), then the temp directory. T-008 appends the spool, T-011
/// the Guard config.
final orphanWipeStepsProvider = Provider<List<OrphanWipeStep>>(
  (ref) => [
    ...dbFileWipeSteps(ref.watch(dbFileSetProvider)),
    ClearDirectoryStep('temp', ref.watch(appTempDirectoryProvider)),
  ],
  name: 'orphanWipeStepsProvider',
);

/// False in the headless engine (T-008): it never migrates.
final allowMigrationProvider = Provider<bool>(
  (ref) => true,
  name: 'allowMigrationProvider',
);

/// Riverpod 3 retries failing providers by default. The open is never
/// retried automatically: a retry is the startup gate's decision
/// (`ref.invalidate`), since an open may wipe or migrate.
Duration? _noRetry(int retryCount, Object error) => null;

/// The open database. Throws [DbOpenFailure] (code only) when it can't be
/// opened; closes the database when disposed.
final appDatabaseProvider = FutureProvider<AppDatabase>(
  (ref) async {
    final result = await openAppDatabase(
      files: ref.watch(dbFileSetProvider),
      bootstrap: ref.watch(keyBootstrapProvider),
      wipeSteps: ref.watch(orphanWipeStepsProvider),
      allowMigration: ref.watch(allowMigrationProvider),
    );
    switch (result) {
      case DbOpened(:final db):
        ref.onDispose(db.close);
        return db;
      case DbOpenFailed(:final code):
        throw DbOpenFailure(code);
    }
  },
  name: 'appDatabaseProvider',
  retry: _noRetry,
);
