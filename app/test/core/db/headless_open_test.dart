// T-008 (Q6, Lead): the headless ingestion engine opens zaghlol.db with
// allowMigration and allowCreateOrWipe false. It never creates the database
// or its key, rotates or deletes a key, wipes an orphan, deletes leftovers or
// recovers a migration: every such case is DB_DEFERRED (gate:
// deferToForeground) with nothing touched, and the lease is released.
// Contract: platform-channels.md §2 "Headless DB rule".
//
// Keys are synthetic (support/synthetic_key.dart); assertions compare codes,
// counts and file snapshots only.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/db_file_set.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import '../../support/synthetic_key.dart';
import 'db_open_harness.dart';

void main() {
  late FakeSecretStore store;
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    store = FakeSecretStore();
    world = await DbWorld.create(store);
  });

  tearDown(() => world.dispose());

  Future<DbOpenResult<AppDatabase>> headless() =>
      world.open(seed: 62, allowMigration: false, allowCreateOrWipe: false);

  Future<void> firstRun() async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    await writeMeta(db, 'marker', 'old');
    await db.close();
  }

  void expectDeferred(DbOpenResult<AppDatabase> r) {
    expect(r, isA<DbOpenFailed<AppDatabase>>());
    final code = (r as DbOpenFailed).code;
    expect(code, DbOpenFailureCode.deferred);
    expect(code.code, 'DB_DEFERRED');
    expect(dbGateStateFor(code), DbGateState.deferToForeground);
  }

  test('no key and no file: nothing is created', () async {
    expectDeferred(await headless());
    expect(store.writeCalls, 0);
    expect(store.stored, isNull);
    expect(world.mainFile.existsSync(), isFalse);
    expect(world.dbDir.existsSync(), isFalse);
    expect(store.leaseHeld, isFalse);
  });

  test('a key but no database (reinstall): the key is not rotated', () async {
    store.stored = syntheticKeyBytes(61);
    expectDeferred(await headless());
    expect(store.writeCalls, 0);
    expect(sameBytes(store.stored!, syntheticKeyBytes(61)), isTrue);
    expect(world.mainFile.existsSync(), isFalse);
    expect(store.leaseHeld, isFalse);
  });

  for (final (label, arrange) in <(String, void Function(FakeSecretStore))>[
    ('missing key', (s) => s.stored = null),
    ('unusable key', (s) => s.forcedStatus = SecretStatus.unusable),
    ('key rejected by SQLite', (s) => s.stored = syntheticKeyBytes(62)),
  ]) {
    test('orphaned database ($label): no wipe, files untouched', () async {
      await firstRun();
      final before = snapshotFiles(world.dbDir);
      arrange(store);
      store.calls.clear();
      expectDeferred(await headless());
      expect(world.wipeLog, isEmpty);
      expect(store.writeCalls, 0);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(store.leaseHeld, isFalse);
    });
  }

  for (final name in [migratePartFileName, migrateTmpFileName]) {
    test('leftover $name: kept (may be the UI engine copying)', () async {
      await firstRun();
      final leftover = File('${world.dbDir.path}/$name')
        ..writeAsBytesSync(const [1, 2, 3]);
      final before = snapshotFiles(world.dbDir);
      expectDeferred(await headless());
      expect(leftover.existsSync(), isTrue);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    });
  }

  test('a file without a schema is not given one', () async {
    store.stored = syntheticKeyBytes(61);
    world.dbDir.createSync(recursive: true);
    world.mainFile.writeAsBytesSync(const []);
    expectDeferred(await headless());
    expect(store.writeCalls, 0);
    // The UI engine (create allowed) still opens it normally afterwards.
    final db = openedDb(await world.open(seed: 61));
    addTearDown(db.close);
  });

  test('an existing database opens normally', () async {
    await firstRun();
    final result = await headless();
    final db = openedDb(result);
    addTearDown(db.close);
    expect((result as DbOpened).created, isFalse);
    expect(await metaValue(db, 'marker'), 'old');
    expect(store.writeCalls, 1, reason: 'only the first run wrote');
  });
}
