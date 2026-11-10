// T-016 §4/§9: the open sequence against FakeSecretStore, real temp
// directories and the host's sqlite3mc. AC1 (wrong key fails cleanly, never a
// wipe on a transient error), the D-50 orphan wipe (order, main file last,
// lease checked before every step), the restore notice, the race between two
// openers, the Riverpod provider and the gate mapping.
//
// Keys are synthetic (support/synthetic_key.dart), never printed or used in a
// test name; assertions compare booleans, counts and codes.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';
import 'package:zaghlol/core/db/migration_guard.dart';
import 'package:zaghlol/core/db/orphan_wipe.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import '../../support/synthetic_key.dart';
import 'db_open_harness.dart';

/// An executor whose open fails like SQLITE_BUSY / SQLITE_IOERR.
DbExecutorFactory transientFailure(int sqliteCode) =>
    (file, key, guard) => NativeDatabase(
      file,
      setup: (_) => throw DbOpenException(
        DbOpenException.openFailed,
        sqliteCode: sqliteCode,
      ),
    );

/// Names step 1 of the open consumes before the bootstrap (a `.migrate.tmp`
/// is rolled back over the main file, a `.part` deleted).
const Set<String> consumedByRecovery = {
  migrateTmpFileName,
  migratePartFileName,
};

/// Creates every other name of the file set next to a real database.
void plantLeftovers(DbFileSet files) {
  for (final name in dbWipeOrder) {
    if (name == dbFileName || consumedByRecovery.contains(name)) continue;
    File('${files.directory.path}/$name').writeAsBytesSync(const [7, 7, 7]);
  }
}

/// A first launch. Foreground, so the connection (and SQLite's deletion of
/// the -wal/-shm files) is closed when this returns.
Future<void> firstRun(DbWorld world) async {
  final db = openedDb(await world.open(executor: foregroundExecutor));
  await writeMeta(db, 'marker', 'old');
  await db.close();
}

void main() {
  late FakeSecretStore store;
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    store = FakeSecretStore();
    world = await DbWorld.create(store);
  });

  tearDown(() => world.dispose());

  group('first run and reopen', () {
    test('no key, no file: creates the key and the database under the '
        'lease, then releases it', () async {
      final result = await world.open();
      expect(result, isA<DbOpened<AppDatabase>>());
      final opened = result as DbOpened<AppDatabase>;
      addTearDown(opened.db.close);
      expect(opened.created, isTrue);
      expect(opened.wipedOrphan, isFalse);
      expect(opened.diagCode, 'DB_OPEN_OK');
      expect(world.mainFile.existsSync(), isTrue);
      expect(store.leaseHeld, isFalse);
      expect(store.renewCalls, 1, reason: 'ensureValid before the create');
      expect(sameBytes(store.stored!, syntheticKeyBytes(61)), isTrue);
      expect(await opened.db.restoreNoticeDue(), isFalse);
    });

    test('second launch: KeyReady opens the same database', () async {
      await firstRun(world);
      final result = await world.open(seed: 62);
      final db = openedDb(result);
      addTearDown(db.close);
      expect((result as DbOpened).created, isFalse);
      expect(await metaValue(db, 'marker'), 'old');
      expect(store.writeCalls, 1, reason: 'only the first create wrote');
    });

    test('the key is zeroized after every open', () async {
      final keys = <DbKeyMaterial>[];
      final db = openedDb(
        await world.open(
          executor: (f, k, g) {
            keys.add(k);
            return defaultDbExecutor(f, k, g);
          },
        ),
      );
      await db.close();
      expect(keys, hasLength(1));
      expect(keys.single.isZeroized, isTrue);
    });
  });

  group('AC1: wrong key fails cleanly', () {
    test(
      'K1 file reopened with K2 → DB_KEY_REJECTED, file bytes unchanged',
      () async {
        await firstRun(world);
        final before = snapshotFiles(world.dbDir);
        final db = AppDatabase(
          openEncryptedExecutor(world.mainFile, keyOf(62)),
          validateSchema: false,
        );
        Object? failure;
        try {
          await db.doWhenOpened((_) {});
        } on Object catch (e) {
          failure = e;
        }
        await db.close();
        expect(dbOpenExceptionOf(failure!)?.code, DbOpenException.keyRejected);
        expect('$failure'.contains(world.root.path), isFalse);
        expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      },
    );

    test('the opener reports the rejection: KeyInvalidated(rejectedBySqlite) '
        '→ wipe, new key, new database with the restore notice', () async {
      await firstRun(world);
      // The store now holds a key the file was not made with.
      store.stored = syntheticKeyBytes(63);
      final result = await world.open(seed: 64);
      final opened = result as DbOpened<AppDatabase>;
      addTearDown(opened.db.close);
      expect(opened.wipedOrphan, isTrue);
      expect(opened.created, isTrue);
      expect(opened.diagCode, 'DB_ORPHAN_WIPED');
      expect(await opened.db.restoreNoticeDue(), isTrue);
      expect(await metaValue(opened.db, 'marker'), isNull);
      expect(sameBytes(store.stored!, syntheticKeyBytes(64)), isTrue);
      expect(world.wipeLog.last, 'temp');
      expect(store.leaseHeld, isFalse);
    });

    test('rejected, but another engine rotated the key meanwhile → one '
        'retry with the new key (no wipe)', () async {
      await firstRun(world);
      // reportRejected re-reads the store: the right key is back.
      final keys = <DbKeyMaterial>[];
      store.stored = syntheticKeyBytes(63);
      var swapped = false;
      final result = await world.open(
        executor: (f, k, g) {
          keys.add(k);
          if (!swapped) {
            swapped = true;
            store.stored = syntheticKeyBytes(61);
          }
          return defaultDbExecutor(f, k, g);
        },
      );
      final db = openedDb(result);
      addTearDown(db.close);
      expect(world.wipeLog, isEmpty);
      expect(keys, hasLength(2));
      expect(await metaValue(db, 'marker'), 'old');
    });

    for (final (name, code) in [('BUSY', 5), ('IOERR', 10)]) {
      test(
        'a $name-style open failure is DB_UNAVAILABLE and never a wipe',
        () async {
          await firstRun(world);
          final before = snapshotFiles(world.dbDir);
          final result = await world.open(executor: transientFailure(code));
          expect(result, isA<DbOpenFailed<AppDatabase>>());
          expect((result as DbOpenFailed).code, DbOpenFailureCode.unavailable);
          expect(world.wipeLog, isEmpty);
          expect(store.writeCalls, 1);
          expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
          expect(store.leaseHeld, isFalse);
        },
      );
    }

    test('a plaintext file at the path is never opened: the key does not '
        'decrypt it, so it is an orphan (D-50) and replaced', () async {
      await world.dbDir.create(recursive: true);
      await ContractPlain(world.mainFile).create();
      store.stored = syntheticKeyBytes(61);
      final result = await world.open();
      final opened = result as DbOpened<AppDatabase>;
      addTearDown(opened.db.close);
      expect(opened.wipedOrphan, isTrue);
      expect(await metaValue(opened.db, 'plain'), isNull);
    });
  });

  group('D-50 orphan wipe', () {
    for (final (label, arrange) in <(String, void Function(FakeSecretStore))>[
      ('missing', (s) => s.stored = null),
      ('unusable', (s) => s.forcedStatus = SecretStatus.unusable),
    ]) {
      test(
        'KeyInvalidated($label): all ${dbWipeOrder.length} names gone, '
        'main file last, temp cleared, new key, new database, notice due',
        () async {
          await firstRun(world);
          plantLeftovers(world.files);
          await world.tempDir.create(recursive: true);
          File('${world.tempDir.path}/cache.bin').writeAsBytesSync([1]);
          arrange(store);
          store.calls.clear();

          final result = await world.open(seed: 62);
          final opened = result as DbOpened<AppDatabase>;
          addTearDown(opened.db.close);
          expect(opened.wipedOrphan, isTrue);
          expect(world.wipeLog, [for (final n in dbWipeOrder) 'db:$n', 'temp']);
          expect(world.wipeLog[dbWipeOrder.length - 1], 'db:$dbFileName');
          expect(world.tempDir.listSync(), isEmpty);
          // Only the new database (open, so with its WAL/SHM) is left.
          expect(
            {
              dbFileName,
              '$dbFileName-wal',
              '$dbFileName-shm',
            }.containsAll(entryNamesOf(world.dbDir)),
            isTrue,
          );
          expect(await opened.db.restoreNoticeDue(), isTrue);
          expect(await metaValue(opened.db, 'marker'), isNull);
          expect(sameBytes(store.stored!, syntheticKeyBytes(62)), isTrue);
          // One renewal per step, one before recreateAfterWipe, one before
          // the create.
          expect(store.renewCalls, world.wipeSteps().length + 2);
          expect(store.leaseHeld, isFalse);
        },
      );
    }

    test('a lease that lapses before step N stops at N-1: the rest stays, '
        'no key written, DB_UNAVAILABLE(leaseLapsed)', () async {
      await firstRun(world);
      plantLeftovers(world.files);
      store.stored = null; // orphan
      const n = 5; // 1-based step that must not run
      store.renewalsBeforeLapse = n - 1;
      final result = await world.open(seed: 62);
      expect(result, isA<DbOpenFailed<AppDatabase>>());
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.unavailable);
      expect(failed.leaseLapsed, isTrue);
      expect(world.wipeLog, [for (final x in dbWipeOrder.take(n - 1)) 'db:$x']);
      for (final x in dbWipeOrder.skip(n - 1)) {
        if (consumedByRecovery.contains(x)) continue;
        expect(File('${world.dbDir.path}/$x').existsSync(), isTrue, reason: x);
      }
      expect(store.stored, isNull, reason: 'no key was written');
      expect(store.createCalls, 1, reason: 'only the first run');

      // Retry (idempotent): the next launch resumes and finishes.
      store.renewalsBeforeLapse = null;
      final retry = await world.open(seed: 62);
      final opened = retry as DbOpened<AppDatabase>;
      addTearDown(opened.db.close);
      expect(opened.wipedOrphan, isTrue);
      expect(await opened.db.restoreNoticeDue(), isTrue);
    });

    test('a lease that lapses before the first create: no file exists, '
        'DB_UNAVAILABLE(leaseLapsed); the next launch re-bootstraps', () async {
      store.renewalsBeforeLapse = 0;
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.unavailable);
      expect(failed.leaseLapsed, isTrue);
      expect(await world.files.anyExists(), isFalse);

      store.renewalsBeforeLapse = null;
      final db = openedDb(await world.open());
      addTearDown(db.close);
      expect(await db.restoreNoticeDue(), isFalse);
    });

    test('a lease that lapses after the wipe: no key is written and no '
        'database created; the next launch starts fresh', () async {
      await firstRun(world);
      store.stored = null;
      // Every wipe step renews once; the next renewal (before
      // recreateAfterWipe writes the key) fails.
      store.renewalsBeforeLapse = world.wipeSteps().length;
      final result = await world.open(seed: 62);
      expect((result as DbOpenFailed).leaseLapsed, isTrue);
      expect(world.mainFile.existsSync(), isFalse);
      expect(store.stored, isNull);
      // Accepted (design note §4): the notice lives in the new database, so
      // an interruption between the wipe and the create loses it.
      store.renewalsBeforeLapse = null;
      final db = openedDb(await world.open(seed: 63));
      addTearDown(db.close);
      expect(world.mainFile.existsSync(), isTrue);
    });

    test(
      'a step that fails is DB_WIPE_INCOMPLETE and nothing is recreated',
      () async {
        await firstRun(world);
        store.stored = null;
        final result = await openAppDatabase(
          files: world.files,
          bootstrap: world.bootstrap(62),
          wipeSteps: [_FailingStep()],
        );
        expect((result as DbOpenFailed).code, DbOpenFailureCode.wipeIncomplete);
        expect(store.stored, isNull);
        expect(world.mainFile.existsSync(), isTrue);
        expect(store.leaseHeld, isFalse);
      },
    );

    test('steps that leave a database file behind → DB_WIPE_INCOMPLETE, no '
        'recreate over leftovers', () async {
      await firstRun(world);
      store.stored = null;
      final steps = dbFileWipeSteps(world.files)
          .where((s) => s.id != 'db:$dbFileName')
          .toList();
      final result = await openAppDatabase(
        files: world.files,
        bootstrap: world.bootstrap(62),
        wipeSteps: steps,
      );
      expect((result as DbOpenFailed).code, DbOpenFailureCode.wipeIncomplete);
      expect(store.stored, isNull);
      expect(store.createCalls, 1);
    });

    test('two openers racing: one wipe, both end with the same new '
        'database', () async {
      await firstRun(world);
      store.stored = null;
      final results = await Future.wait([
        world.open(seed: 62),
        world.open(seed: 63),
      ]);
      final dbs = [for (final r in results) openedDb(r)];
      for (final db in dbs) {
        addTearDown(db.close);
      }
      expect(world.wipeLog.where((x) => x == 'db:$dbFileName'), hasLength(1));
      expect(
        results.whereType<DbOpened<AppDatabase>>().where((r) => r.wipedOrphan),
        hasLength(1),
      );
      // Either opener may win the lease; the key is the winner's.
      final winner = (results[0] as DbOpened<AppDatabase>).wipedOrphan
          ? 62
          : 63;
      expect(sameBytes(store.stored!, syntheticKeyBytes(winner)), isTrue);
      await writeMeta(dbs[0], 'shared', 'yes');
      expect(await metaValue(dbs[1], 'shared'), 'yes');
    });

    test('the only secret ever deleted is the database key', () async {
      await firstRun(world);
      store.stored = null;
      store.calls.clear();
      final db = openedDb(await world.open(seed: 62));
      addTearDown(db.close);
      // SecretSlot has dbKey only; the wipe steps never call the store.
      expect(SecretSlot.values, [SecretSlot.dbKey]);
      expect(store.deleteCalls, 1);
    });
  });

  test('dbFileWipeSteps deletes all ${dbWipeOrder.length} names, main file '
      'last, and is idempotent', () async {
    await world.dbDir.create(recursive: true);
    for (final name in dbWipeOrder) {
      File('${world.dbDir.path}/$name').writeAsBytesSync(const [7]);
    }
    expect(dbWipeOrder.toSet(), hasLength(13));
    expect(dbWipeOrder.toSet(), {...dbFileNames, migratePartFileName});
    expect(dbWipeOrder.last, dbFileName);
    final log = <String>[];
    final mainSeen = <bool>[];
    for (final step in dbFileWipeSteps(world.files)) {
      log.add(step.id);
      mainSeen.add(world.mainFile.existsSync());
      await step.run();
    }
    expect(
      mainSeen.every((exists) => exists),
      isTrue,
      reason: 'the main file exists until the last step',
    );
    expect(log.last, 'db:$dbFileName');
    expect(world.dbDir.listSync(), isEmpty);
    expect(await world.files.anyExists(), isFalse);
    for (final step in dbFileWipeSteps(world.files)) {
      await step.run();
    }
  });

  group('other bootstrap outcomes', () {
    test('KeyUnavailable → DB_UNAVAILABLE, nothing touched', () async {
      await firstRun(world);
      store.forcedStatus = SecretStatus.unavailable;
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      expect((result as DbOpenFailed).code, DbOpenFailureCode.unavailable);
      expect(world.wipeLog, isEmpty);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    });

    test('lease timeout → DB_UNAVAILABLE', () async {
      store.failAcquire = SecretStoreErrorCode.leaseTimeout;
      final result = await world.open();
      expect((result as DbOpenFailed).code, DbOpenFailureCode.unavailable);
    });

    test('KeyStoreFailed → DB_STORE_FAILED, no file created', () async {
      store.failCreate = SecretStoreErrorCode.storeFailed;
      final result = await world.open();
      expect((result as DbOpenFailed).code, DbOpenFailureCode.storeFailed);
      expect(await world.files.anyExists(), isFalse);
    });

    test('leftovers without a main file (key present): deleted, then the '
        'rotate path creates a fresh database without a notice', () async {
      store.stored = syntheticKeyBytes(61);
      await world.dbDir.create(recursive: true);
      File('${world.mainFile.path}-wal').writeAsBytesSync([1, 2, 3]);
      final result = await world.open(seed: 62);
      final opened = result as DbOpened<AppDatabase>;
      addTearDown(opened.db.close);
      expect(opened.created, isTrue);
      expect(opened.wipedOrphan, isFalse);
      expect(await opened.db.restoreNoticeDue(), isFalse);
      expect(sameBytes(store.stored!, syntheticKeyBytes(62)), isTrue);
    });
  });

  group('gate and diag', () {
    test('every failure code maps to a gate state', () {
      expect(DbOpenFailureCode.values, hasLength(7));
      final codes = <String>{};
      for (final c in DbOpenFailureCode.values) {
        expect(DbGateState.values, contains(dbGateStateFor(c)));
        expect(RegExp(r'^DB_[A-Z_]+$').hasMatch(c.code), isTrue);
        codes.add(c.code);
      }
      expect(codes, hasLength(DbOpenFailureCode.values.length));
      expect(
        dbGateStateFor(DbOpenFailureCode.migrationFailed),
        DbGateState.updateFailed,
      );
      expect(
        dbGateStateFor(DbOpenFailureCode.migrationPending),
        DbGateState.deferToForeground,
      );
    });

    test(
      'diag fields are {code, fromVersion, toVersion, platform} only',
      () async {
        final result = await world.open();
        openedDb(result);
        await (result as DbOpened<AppDatabase>).db.close();
        expect(result.diagFields('android').keys.toSet(), {
          'code',
          'fromVersion',
          'toVersion',
          'platform',
        });
        const failed = DbOpenFailed<AppDatabase>(
          DbOpenFailureCode.unavailable,
          toVersion: 1,
        );
        expect(failed.diagFields('ios').keys.toSet(), {
          'code',
          'fromVersion',
          'toVersion',
          'platform',
        });
        expect('$failed', 'DbOpenFailed(DB_UNAVAILABLE)');
      },
    );

    test('DbOpenFailure is code-only', () {
      final e = DbOpenFailure(DbOpenFailureCode.schemaTooNew);
      expect('$e', 'DB_SCHEMA_TOO_NEW');
    });
  });

  group('Riverpod', () {
    ProviderContainer container({bool autoDispose = true}) {
      final c = ProviderContainer(
        overrides: [
          secretStoreProvider.overrideWithValue(store),
          dbDirectoryProvider.overrideWithValue(world.dbDir),
          keyGeneratorProvider.overrideWithValue(FixedKeyGenerator(61)),
          appTempDirectoryProvider.overrideWithValue(() async => world.tempDir),
        ],
      );
      if (autoDispose) addTearDown(c.dispose);
      return c;
    }

    test('appDatabaseProvider opens the database; dispose closes it', () async {
      final c = container(autoDispose: false);
      final db = await c.read(appDatabaseProvider.future);
      await writeMeta(db, 'p', '1');
      expect(await metaValue(db, 'p'), '1');
      c.dispose();
      // Closed: the next container opens the same file again.
      final again = await container().read(appDatabaseProvider.future);
      expect(await metaValue(again, 'p'), '1');
    });

    test('a failure surfaces as DbOpenFailure with the code', () async {
      store.failCreate = SecretStoreErrorCode.storeFailed;
      final c = container();
      Object? error;
      try {
        await c.read(appDatabaseProvider.future);
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<DbOpenFailure>());
      expect((error! as DbOpenFailure).failure, DbOpenFailureCode.storeFailed);
      expect(store.createCalls, 1, reason: 'no automatic retry');
    });

    test('the wipe steps: db files in wipe order, then temp', () {
      final steps = container().read(orphanWipeStepsProvider);
      expect(
        [for (final s in steps) s.id],
        [for (final n in dbWipeOrder) 'db:$n', 'temp'],
      );
    });

    test('allowMigrationProvider defaults to true', () {
      expect(container().read(allowMigrationProvider), isTrue);
    });
  });

  test('BootstrapLease.ensureValid: renews, and throws DB_LEASE_LAPSED when '
      'released, lapsed or unconfirmable', () async {
    await world.dbDir.create(recursive: true);
    final created = await world.bootstrap().obtain() as KeyCreated;
    final lease = created.lease;
    await lease.ensureValid();
    expect(store.renewCalls, 1);

    store.failRenew = true;
    await expectLater(lease.ensureValid(), throwsA(_leaseLapsed));
    store.failRenew = false;

    store.renewalsBeforeLapse = 0;
    await expectLater(lease.ensureValid(), throwsA(_leaseLapsed));
    expect(store.leaseHeld, isFalse);

    await lease.release();
    final calls = store.renewCalls;
    await expectLater(lease.ensureValid(), throwsA(_leaseLapsed));
    expect(store.renewCalls, calls, reason: 'released: no native call');
    created.key.zeroize();
  });

  test('copyFileForMigration copies bytes exactly', () async {
    await world.root.create(recursive: true);
    final src = File('${world.root.path}/src.bin')
      ..writeAsBytesSync(
        Uint8List.fromList([
          for (var i = 0; i < 3 * 1024 * 1024 + 17; i++) i & 0xFF,
        ]),
      );
    final dst = File('${world.root.path}/dst.bin')..writeAsBytesSync([9, 9]);
    copyFileForMigration(src, dst);
    expect(sameBytes(src.readAsBytesSync(), dst.readAsBytesSync()), isTrue);
  });
}

final Matcher _leaseLapsed = isA<DbOpenException>().having(
  (e) => e.code,
  'code',
  DbOpenException.leaseLapsed,
);

final class _FailingStep implements OrphanWipeStep {
  @override
  String get id => 'failing';

  @override
  Future<void> run() async =>
      throw const FileSystemException('synthetic: busy');
}

Set<String> entryNamesOf(Directory dir) => {
  for (final e in dir.listSync()) e.uri.pathSegments.lastWhere((p) => p != ''),
};

/// A plaintext SQLite file at the database path.
final class ContractPlain {
  ContractPlain(this.file);
  final File file;

  Future<void> create() async {
    final db = AppDatabase(NativeDatabase(file), validateSchema: false);
    await db.customStatement("INSERT INTO db_meta VALUES ('plain', '1')");
    await db.close();
  }
}
