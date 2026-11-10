// T-016 §6 (AC3, NFR-REL-02): the migration safety net on a real encrypted
// file, with the synthetic schema v2 (fake_v2_database.dart). Success deletes
// the copy; a failing step (or an FK violation) restores byte-identical files
// and the old version reopens; an unconfirmed migration at startup is rolled
// back; a `.part` is ignored; a failed copy migrates nothing; a newer file is
// refused untouched; the headless engine never migrates; the copy is
// encrypted with the same key.
//
// Keys are synthetic, never printed.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'db_open_harness.dart';
import 'fake_v2_database.dart';
import 'sqlite3mc_contract.dart' show hasPlaintextHeader;

/// Makes a v1 database with one marker row (foreground, so it is fully
/// closed, -wal/-shm deleted, when this returns).
Future<void> makeV1(DbWorld world, {String marker = 'v1'}) async {
  final db = openedDb(await world.open(executor: foregroundExecutor));
  await writeMeta(db, 'marker', marker);
  await db.close();
}

void main() {
  late FakeSecretStore store;
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    store = FakeSecretStore();
    world = await DbWorld.create(store, tag: 't016_mig');
  });

  tearDown(() => world.dispose());

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';
    final executor = background ? defaultDbExecutor : foregroundExecutor;

    test('success: v1 → v2 runs the step once, confirms and deletes the '
        'copy ($mode)', () async {
      await makeV1(world);
      final result = await world.openWith(
        fakeV2Factory(),
        FakeV2Database.version,
        executor: executor,
      );
      final opened = result as DbOpened<FakeV2Database>;
      addTearDown(opened.db.close);
      expect(opened.migratedFrom, 1);
      expect(opened.diagCode, 'DB_MIGRATED');
      expect(opened.db.steps, 1);
      expect(await userVersionOf(opened.db), 2);
      expect(await metaValue(opened.db, 'fake_v2'), '1');
      expect(await metaValue(opened.db, 'marker'), 'v1');
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);
      expect(
        await opened.db
            .customSelect('PRAGMA foreign_keys')
            .getSingle()
            .then((r) => r.data.values.single),
        1,
      );
    });

    for (final failMode in [FakeV2Mode.throwInStep, FakeV2Mode.fkViolation]) {
      test('AC3: ${failMode.name} → DB_MIGRATION_FAILED(restored), every '
          'file byte-identical, the old version reopens ($mode)', () async {
        await makeV1(world);
        final before = snapshotFiles(world.dbDir);
        expect(before.keys, [dbFileName]);

        final result = await world.openWith(
          fakeV2Factory(mode: failMode),
          FakeV2Database.version,
          executor: executor,
        );
        expect(result, isA<DbOpenFailed<FakeV2Database>>());
        final failed = result as DbOpenFailed;
        expect(failed.code, DbOpenFailureCode.migrationFailed);
        expect(failed.restored, isTrue);
        expect(failed.diagCode, 'DB_MIGRATION_FAILED');
        expect(failed.fromVersion, 1);
        expect(failed.toVersion, 2);
        expect(dbGateStateFor(failed.code), DbGateState.updateFailed);
        await settle(world);
        expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
        expect(store.leaseHeld, isFalse);
        expect(world.wipeLog, isEmpty);

        final v1 = openedDb(await world.open(executor: foregroundExecutor));
        addTearDown(v1.close);
        expect(await userVersionOf(v1), 1);
        expect(await metaValue(v1, 'marker'), 'v1');
        expect(await metaValue(v1, 'fake_v2'), isNull);
      });
    }
  }

  test('AC3: a step that damaged the main file outside SQLite is undone: '
      'the restored file is the copy, byte for byte', () async {
    await makeV1(world);
    final before = snapshotFiles(world.dbDir);
    final result = await world.openWith(
      fakeV2Factory(
        mode: FakeV2Mode.throwInStep,
        // Simulates a non-transactional partial write.
        onStep: () => world.mainFile.writeAsBytesSync(
          List<int>.filled(4096, 0xEE),
          mode: FileMode.append,
          flush: true,
        ),
      ),
      FakeV2Database.version,
    );
    expect((result as DbOpenFailed).restored, isTrue);
    await settle(world);
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
  });

  test('crash after the copy, before confirmation: the next start rolls '
      'back to the copy', () async {
    await makeV1(world, marker: 'before');
    final copy = world.mainFile.readAsBytesSync();
    // A "migration" that wrote, then the process died: the main file has
    // changed and the copy is still there.
    final db = rawAppDatabase(world.mainFile);
    await writeMeta(db, 'marker', 'after-crash');
    await db.close();
    world.files.migrateTmp.writeAsBytesSync(copy, flush: true);

    final v1 = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(v1.close);
    expect(await metaValue(v1, 'marker'), 'before');
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  test('a leftover .part is ignored and deleted', () async {
    await makeV1(world);
    world.files.migratePart.writeAsBytesSync([1, 2, 3]);
    File('${world.files.migratePart.path}-wal').writeAsBytesSync([4]);
    final db = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(db.close);
    expect(await metaValue(db, 'marker'), 'v1');
    expect(world.files.migratePart.existsSync(), isFalse);
    expect(File('${world.files.migratePart.path}-wal').existsSync(), isFalse);
  });

  for (final background in [true, false]) {
    test('disk full while copying: DB_MIGRATE_COPY_FAILED, nothing migrated, '
        'no copy left (${background ? 'background' : 'foreground'})', () async {
      await makeV1(world);
      final before = snapshotFiles(world.dbDir);
      final opened = <FakeV2Database>[];
      final result = await world.openWith(
        fakeV2Factory(opened: opened),
        FakeV2Database.version,
        copier: diskFullCopier,
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      expect(
        (result as DbOpenFailed).code,
        DbOpenFailureCode.migrateCopyFailed,
      );
      expect(opened.single.steps, 0);
      await settle(world);
      expect(world.files.migratePart.existsSync(), isFalse);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    });
  }

  test('too new (v3 file, v1 app): DB_SCHEMA_TOO_NEW, file untouched '
      '(EC-26)', () async {
    await makeV1(world);
    final db = rawAppDatabase(world.mainFile);
    await db.customStatement('PRAGMA user_version = 3');
    await db.close();
    final before = snapshotFiles(world.dbDir);

    final result = await world.open(executor: foregroundExecutor);
    expect((result as DbOpenFailed).code, DbOpenFailureCode.schemaTooNew);
    expect(
      dbGateStateFor((result as DbOpenFailed).code),
      DbGateState.appUpdateRequired,
    );
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    expect(world.wipeLog, isEmpty);
  });

  test('headless engine (allowMigration: false): DB_MIGRATION_PENDING, file '
      'untouched, no copy', () async {
    await makeV1(world);
    final before = snapshotFiles(world.dbDir);
    final opened = <FakeV2Database>[];
    final result = await world.openWith(
      fakeV2Factory(opened: opened),
      FakeV2Database.version,
      allowMigration: false,
      executor: foregroundExecutor,
    );
    expect((result as DbOpenFailed).code, DbOpenFailureCode.migrationPending);
    expect(
      dbGateStateFor((result as DbOpenFailed).code),
      DbGateState.deferToForeground,
    );
    expect(opened.single.steps, 0);
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
  });

  test('headless engine never rolls back an unconfirmed migration (the UI '
      'engine may be migrating): DB_MIGRATION_PENDING, copy kept', () async {
    await makeV1(world);
    world.files.migrateTmp.writeAsBytesSync(world.mainFile.readAsBytesSync());
    final before = snapshotFiles(world.dbDir);
    final result = await world.open(allowMigration: false);
    expect((result as DbOpenFailed).code, DbOpenFailureCode.migrationPending);
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
  });

  group('review M-1: only a copy made by this open is ever restored', () {
    for (final background in [true, false]) {
      final mode = background ? 'background' : 'foreground';
      final engine = background ? defaultDbExecutor : foregroundExecutor;

      test('two engines: the UI engine is migrating (copy present, live '
          '-wal/-shm); the headless engine\'s open fails → '
          'DB_MIGRATION_PENDING; main file, -wal, -shm and the copy are '
          'untouched and the UI engine loses nothing ($mode)', () async {
        await makeV1(world);
        // The UI engine: a live connection with uncheckpointed writes.
        final ui = rawAppDatabase(world.mainFile);
        await writeMeta(ui, 'ui', 'one');
        final wal = File('${world.mainFile.path}-wal');
        final shm = File('${world.mainFile.path}-shm');
        expect(wal.existsSync(), isTrue);
        expect(shm.existsSync(), isTrue);
        final copyBytes = world.mainFile.readAsBytesSync();

        // The UI engine's copy appears after the headless engine's step 1
        // (step 1 alone already defers when it sees a copy).
        Map<String, Uint8List>? before;
        final opened = <FakeV2Database>[];
        final result = await world.openWith(
          fakeV2Factory(opened: opened),
          FakeV2Database.version,
          allowMigration: false,
          executor: (file, key, guard) {
            world.files.migrateTmp.writeAsBytesSync(copyBytes, flush: true);
            before = snapshotFiles(world.dbDir);
            return engine(file, key, guard);
          },
        );
        final failed = result as DbOpenFailed;
        expect(failed.code, DbOpenFailureCode.migrationPending);
        expect(failed.restored, isNull);
        expect(opened.single.steps, 0);

        final after = snapshotFiles(world.dbDir);
        for (final name in [
          dbFileName,
          '$dbFileName-wal',
          migrateTmpFileName,
        ]) {
          expect(after.containsKey(name), isTrue, reason: name);
          expect(sameBytes(before![name]!, after[name]!), isTrue, reason: name);
        }
        expect(shm.existsSync(), isTrue);
        expect(world.wipeLog, isEmpty);

        // The UI engine keeps writing into the live file, not an unlinked one.
        await writeMeta(ui, 'ui', 'two');
        await ui.close();
        world.files.migrateTmp.deleteSync(); // the UI engine confirms
        final check = rawAppDatabase(world.mainFile);
        addTearDown(check.close);
        expect(await metaValue(check, 'ui'), 'two');
        expect(await metaValue(check, 'marker'), 'v1');
      });
    }

    test('an engine that may migrate but did not upgrade (DB_SCHEMA_TOO_NEW) '
        'leaves a copy that appeared after step 1 alone', () async {
      await makeV1(world);
      final db = rawAppDatabase(world.mainFile);
      await db.customStatement('PRAGMA user_version = 3');
      await db.close();
      final copyBytes = world.mainFile.readAsBytesSync();
      Map<String, Uint8List>? before;
      final result = await world.open(
        executor: (file, key, guard) {
          world.files.migrateTmp.writeAsBytesSync(copyBytes, flush: true);
          before = snapshotFiles(world.dbDir);
          return foregroundExecutor(file, key, guard);
        },
      );
      expect((result as DbOpenFailed).code, DbOpenFailureCode.schemaTooNew);
      expect(sameSnapshot(before!, snapshotFiles(world.dbDir)), isTrue);
    });

    test('an engine that opened without upgrading never confirms (deletes) '
        'another engine\'s copy', () async {
      await makeV1(world);
      final copyBytes = world.mainFile.readAsBytesSync();
      final result = await world.open(
        executor: (file, key, guard) {
          world.files.migrateTmp.writeAsBytesSync(copyBytes, flush: true);
          return foregroundExecutor(file, key, guard);
        },
      );
      final db = openedDb(result);
      addTearDown(db.close);
      expect(world.files.migrateTmp.existsSync(), isTrue);
    });
  });

  test('the copy is the encrypted file: header is not "SQLite format 3" and '
      'it opens with the same key', () async {
    await makeV1(world);
    final evidence = File('${world.root.path}/evidence.db');
    var header = true;
    final result = await world.openWith(
      fakeV2Factory(
        mode: FakeV2Mode.throwInStep,
        onStep: () {
          header = hasPlaintextHeader(world.files.migrateTmp);
          world.files.migrateTmp.copySync(evidence.path);
        },
      ),
      FakeV2Database.version,
    );
    expect((result as DbOpenFailed).restored, isTrue);
    expect(header, isFalse);
    expect(hasPlaintextHeader(evidence), isFalse);
    final copy = AppDatabase(
      openEncryptedExecutor(evidence, keyOf(61), inBackground: false),
      validateSchema: false,
    );
    addTearDown(copy.close);
    expect(await metaValue(copy, 'marker'), 'v1');
    expect(await userVersionOf(copy), 1);
    // And not with another key.
    final wrong = AppDatabase(
      openEncryptedExecutor(
        File('${world.root.path}/evidence2.db')
          ..writeAsBytesSync(Uint8List.fromList(evidence.readAsBytesSync())),
        keyOf(62),
        inBackground: false,
      ),
      validateSchema: false,
    );
    Object? failure;
    try {
      await wrong.doWhenOpened((_) {});
    } on Object catch (e) {
      failure = e;
    }
    await wrong.close();
    expect(dbOpenExceptionOf(failure!)?.isKeyRejected, isTrue);
  });

  test('a v1 app has no migration path: an older file (v0 with tables) is '
      'created, a v1 file opens without a copy', () async {
    await makeV1(world);
    final db = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(db.close);
    expect(world.files.migrateTmp.existsSync(), isFalse);
    expect(db.attemptedUpgradeFrom, isNull);
  });
}

/// Lets a background isolate finish closing (SQLite deletes -wal/-shm on the
/// last close) before files are compared.
Future<void> settle(DbWorld world) async {
  for (var i = 0; i < 50; i++) {
    final names = world.dbDir.listSync().map((e) => e.uri.pathSegments.last);
    if (!names.any((n) => n.endsWith('-wal') || n.endsWith('-shm'))) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
