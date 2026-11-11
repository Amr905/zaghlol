// T-016: shared helpers for the database open tests (host and device). A
// temp directory per test, a key bootstrap over any SecretStore, wipe steps
// that record their order, and small database readers.
//
// Keys are synthetic (support/synthetic_key.dart) and never printed.

import 'dart:io';

import 'package:drift/drift.dart'
    show GeneratedDatabase, QueryExecutor, Variable;
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';
import 'package:zaghlol/core/db/migration_guard.dart';
import 'package:zaghlol/core/db/orphan_wipe.dart';

import '../../support/synthetic_key.dart';

/// A wipe step that records when it ran.
final class RecordingStep implements OrphanWipeStep {
  RecordingStep(this._inner, this._log);

  final OrphanWipeStep _inner;
  final List<String> _log;

  @override
  String get id => _inner.id;

  @override
  Future<void> run() async {
    _log.add(id);
    await _inner.run();
  }
}

/// One test's database world: a temp directory with `db/` and `tmp/`, a
/// store, and the opener wired like the app (background executor).
final class DbWorld {
  DbWorld._(this.root, this.store);

  static Future<DbWorld> create(
    SecretStore store, {
    String tag = 't016',
  }) async {
    final root = await Directory.systemTemp.createTemp('zaghlol_${tag}_');
    return DbWorld._(root, store);
  }

  final Directory root;
  final SecretStore store;

  /// Every wipe step that ran, in order (across opens).
  final List<String> wipeLog = [];

  Directory get dbDir => Directory('${root.path}/db');
  Directory get tempDir => Directory('${root.path}/tmp');
  DbFileSet get files => DbFileSet(dbDir);
  File get mainFile => files.mainFile;

  KeyBootstrap bootstrap([int seed = 61]) => KeyBootstrap(
    store: store,
    files: files,
    generator: FixedKeyGenerator(seed),
    leaseTimeout: const Duration(seconds: 35),
  );

  /// The app's steps (db files in wipe order, then the temp dir), recorded.
  List<OrphanWipeStep> wipeSteps() => [
    for (final s in [
      ...dbFileWipeSteps(files),
      ClearDirectoryStep('temp', () async => tempDir),
    ])
      RecordingStep(s, wipeLog),
  ];

  Future<DbOpenResult<AppDatabase>> open({
    int seed = 61,
    bool allowMigration = true,
    bool allowCreateOrWipe = true,
    DbExecutorFactory executor = defaultDbExecutor,
    MigrationCopier copier = copyFileForMigration,
    List<OrphanWipeStep>? steps,
  }) => openAppDatabase(
    files: files,
    bootstrap: bootstrap(seed),
    wipeSteps: steps ?? wipeSteps(),
    allowMigration: allowMigration,
    allowCreateOrWipe: allowCreateOrWipe,
    executor: executor,
    copier: copier,
  );

  Future<DbOpenResult<D>> openWith<D extends GeneratedDatabase>(
    DatabaseFactory<D> database,
    int schemaVersion, {
    int seed = 61,
    bool allowMigration = true,
    DbExecutorFactory executor = defaultDbExecutor,
    MigrationCopier copier = copyFileForMigration,
  }) => openDatabaseWith<D>(
    files: files,
    bootstrap: bootstrap(seed),
    wipeSteps: wipeSteps(),
    database: database,
    schemaVersion: schemaVersion,
    allowMigration: allowMigration,
    executor: executor,
    copier: copier,
  );

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// The foreground executor (same sequence, no isolate).
QueryExecutor foregroundExecutor(
  File file,
  DbKeyMaterial key,
  MigrationGuard guard,
) => openEncryptedExecutor(file, key, guard: guard, inBackground: false);

/// A fresh copy of the synthetic key [seed].
DbKeyMaterial keyOf(int seed) => DbKeyMaterial.copyOf(syntheticKeyBytes(seed));

/// The opened database, or a test failure naming the code.
D openedDb<D>(DbOpenResult<D> result) => switch (result) {
  DbOpened(:final db) => db,
  DbOpenFailed(:final code) => throw StateError('expected open: ${code.code}'),
};

/// Opens [file] with the synthetic key [seed] outside the opener (no guard,
/// no migration check), as a plain AppDatabase.
AppDatabase rawAppDatabase(
  File file, {
  int seed = 61,
  bool background = false,
}) => AppDatabase(
  openEncryptedExecutor(
    file,
    DbKeyMaterial.copyOf(syntheticKeyBytes(seed)),
    inBackground: background,
  ),
  validateSchema: false,
);

Future<int> userVersionOf(GeneratedDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single
        as int;

Future<String?> metaValue(GeneratedDatabase db, String key) async {
  final rows = await db
      .customSelect(
        'SELECT value FROM db_meta WHERE key = ?',
        variables: [Variable.withString(key)],
      )
      .get();
  return rows.isEmpty ? null : rows.single.data['value'] as String?;
}

/// Writes one synthetic `db_meta` row and closes.
Future<void> writeMeta(AppDatabase db, String key, String value) =>
    db.customStatement(
      'INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)',
      [key, value],
    );
