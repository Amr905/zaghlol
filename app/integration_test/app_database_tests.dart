// T-016: AppDatabase on the real Keystore / Keychain and the shipped
// sqlite3mc binaries (design note §9). Registered by db_platform_test.dart, so
// db-platform.yml runs it on the Android API 35 / API 26 emulators and the iOS
// simulator in the same app launch as T-007 and T-015 (a second launch hung
// on CI). Standalone, e.g. on devices:
//   flutter test integration_test/app_database_test.dart --flavor devNoSms -d <id>
//
// AC1: wrong key fails cleanly (DB_KEY_REJECTED, bytes unchanged); the opener
//      turns the rejection into an orphan wipe; a transient failure is
//      DB_UNAVAILABLE and never a wipe.
// AC2: the header of zaghlol.db and of the pre-migration copy is not
//      "SQLite format 3"; WAL/SHM hold no sentinel (with a positive control).
// AC3: a failing migration restores byte-identical files; the old version
//      reopens. D-50: a deleted key wipes every file (main last) and the new
//      database carries the restore notice.
// T-017: the real v1 → v2 step on the device's sqlite3mc (FTS5 trigram and
//      unicode61 tables, offset triggers, CHECKs) through the app's opener.
// T-018: v1 files now migrate to v3; the real v2 → v3 step on a populated
//      file (catalog trigram candidates, FTS5 secure-delete set and
//      effective on this sqlite3mc, the T-017 review trigger fixes).
//
// Hygiene: keys are synthetic and never printed; assertions compare
// booleans, counts and codes. Nothing is printed.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/schema_shape.dart';
import 'package:zaghlol/core/platform/pigeon_secret_store.dart';

import '../test/core/db/db_open_harness.dart';
import '../test/core/db/fake_next_database.dart';
import '../test/core/db/financial_fixtures.dart'
    show account, failureOf, link, txn;
import '../test/core/db/fts_probe.dart';
import '../test/core/db/schema_v1_database.dart';
import '../test/core/db/schema_v2_database.dart';
import '../test/core/db/sqlite3mc_contract.dart'
    show anyFileContains, hasPlaintextHeader;
import '../test/support/file_snapshot.dart';
import '../test/support/synthetic_key.dart';

/// Registers the T-016 device tests. The caller initialises the integration
/// test binding; wrap the call in a `group` to scope setUp/tearDown.
void registerAppDatabaseTests() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final store = PigeonSecretStore();
  late DbWorld world;

  Future<void> resetSlot() async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 35),
    );
    try {
      await store.delete(lease, SecretSlot.dbKey);
    } finally {
      await store.releaseBootstrapLease(lease);
    }
  }

  /// Stores [seed] as the database key (the slot must be empty).
  Future<void> storeKey(int seed) async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 35),
    );
    try {
      await store.createIfAbsent(
        lease,
        SecretSlot.dbKey,
        syntheticKeyBytes(seed),
      );
    } finally {
      await store.releaseBootstrapLease(lease);
    }
  }

  Future<void> firstRun() async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    await writeMeta(db, 'marker', 'old');
    await db.close();
  }

  setUp(() async {
    await resetSlot();
    world = await DbWorld.create(store, tag: 't016_it');
  });

  tearDown(() async {
    await world.dispose();
    await resetSlot();
  });

  test(
    'renewBootstrapLease: true for the held lease, false after release',
    () async {
      final lease = await store.acquireBootstrapLease(
        const Duration(seconds: 35),
      );
      expect(await store.renewBootstrapLease(lease), isTrue);
      await store.releaseBootstrapLease(lease);
      expect(await store.renewBootstrapLease(lease), isFalse);
    },
  );

  test(
    'AC1: K1 file reopened with K2 → DB_KEY_REJECTED, bytes unchanged',
    () async {
      await firstRun();
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
      expect(dbOpenExceptionOf(failure!)?.isKeyRejected, isTrue);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    },
  );

  test('AC1: stored key does not open the file → orphan wipe, new key, new '
      'database with the restore notice', () async {
    await firstRun();
    await resetSlot();
    await storeKey(63);
    final result = await world.open(seed: 64);
    final opened = result as DbOpened<AppDatabase>;
    expect(opened.wipedOrphan, isTrue);
    expect(await opened.db.restoreNoticeDue(), isTrue);
    expect(await metaValue(opened.db, 'marker'), isNull);
    await opened.db.close();
    final read = await store.read(SecretSlot.dbKey);
    expect(sameBytes(read.value!, syntheticKeyBytes(64)), isTrue);
    read.value!.fillRange(0, read.value!.length, 0);
  });

  test(
    'AC1: a BUSY/IOERR-style failure is DB_UNAVAILABLE, never a wipe',
    () async {
      await firstRun();
      final before = snapshotFiles(world.dbDir);
      final result = await world.open(
        executor: (file, key, guard) => NativeDatabase(
          file,
          setup: (_) =>
              throw DbOpenException(DbOpenException.openFailed, sqliteCode: 10),
        ),
      );
      expect((result as DbOpenFailed).code, DbOpenFailureCode.unavailable);
      expect(world.wipeLog, isEmpty);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect((await store.read(SecretSlot.dbKey)).status, SecretStatus.found);
    },
  );

  test('AC2: zaghlol.db header is not "SQLite format 3"; WAL/SHM hold no '
      'sentinel', () async {
    final db = openedDb(await world.open());
    const latin = 'T016DEVICESENTINEL';
    const arabic = 'زغلول_جهاز_تي١٦';
    for (var i = 0; i < 50; i++) {
      await writeMeta(db, 'k$i', '$latin $arabic $i');
    }
    final needles = [utf8.encode(latin), utf8.encode(arabic)];
    final files = [
      world.mainFile,
      File('${world.mainFile.path}-wal'),
      File('${world.mainFile.path}-shm'),
    ];
    expect(hasPlaintextHeader(world.mainFile), isFalse);
    expect(anyFileContains(files, needles), isFalse);
    await db.close();
    final control = File('${world.root.path}/control.bin')
      ..writeAsBytesSync([0, ...needles[0], 0]);
    expect(anyFileContains([control], needles), isTrue);
  });

  test('AC3: a failing current → next step restores byte-identical files; '
      'the copy was encrypted; the current version reopens', () async {
    await firstRun();
    final before = snapshotFiles(world.dbDir);
    var copyHeaderPlain = true;
    final result = await world.openWith(
      fakeNextFactory(
        mode: FakeNextMode.throwInStep,
        onStep: () {
          copyHeaderPlain = hasPlaintextHeader(world.files.migrateTmp);
          world.mainFile.writeAsBytesSync(
            List<int>.filled(4096, 0xEE),
            mode: FileMode.append,
            flush: true,
          );
        },
      ),
      FakeNextDatabase.version,
    );
    final failed = result as DbOpenFailed;
    expect(failed.code, DbOpenFailureCode.migrationFailed);
    expect(failed.restored, isTrue);
    expect(copyHeaderPlain, isFalse);
    for (var i = 0; i < 50; i++) {
      final names = world.dbDir.listSync().map((e) => e.uri.pathSegments.last);
      if (!names.any((n) => n.endsWith('-wal') || n.endsWith('-shm'))) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);

    final current = openedDb(await world.open());
    expect(await userVersionOf(current), appSchemaVersion);
    expect(await metaValue(current, 'marker'), 'old');
    await current.close();
  });

  test('AC3: a successful current → next migration deletes the copy', () async {
    await firstRun();
    final result = await world.openWith(
      fakeNextFactory(),
      FakeNextDatabase.version,
    );
    final opened = result as DbOpened<FakeNextDatabase>;
    expect(opened.migratedFrom, appSchemaVersion);
    expect(await userVersionOf(opened.db), FakeNextDatabase.version);
    expect(world.files.migrateTmp.existsSync(), isFalse);
    await opened.db.close();
  });

  test(
    'T-017: v1 → latest on this device: copy deleted, schema = fresh, '
    'Arabic/English search in both FTS tables, offset trigger, CHECKs',
    () async {
      await storeKey(61);
      await makeV1File(world.mainFile);
      final result = await world.open();
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      try {
        expect(opened.migratedFrom, 1);
        expect(await userVersionOf(db), appSchemaVersion);
        expect(world.files.migrateTmp.existsSync(), isFalse);
        expect(await metaValue(db, 'marker'), 'v1');
        final fresh = AppDatabase(
          NativeDatabase.memory(),
          validateSchema: false,
        );
        final freshShape = await schemaShapeOf(fresh);
        await fresh.close();
        expect(sameSchemaShape(await schemaShapeOf(db), freshShape), isTrue);

        await AccountsDao(db).insert(account('acc1'));
        final txns = TransactionsDao(db);
        await txns.insert(
          txn('e1', merchant: 'كارفور المعادي', amountMinor: 125050),
        );
        await txns.insert(
          txn('e2', merchant: 'Café Zamalek', amountMinor: 900),
        );
        await txns.insert(txn('i1', direction: 'income', amountMinor: 1000));
        Future<List<String>> ids(String q) async => [
          for (final r in await txns.search(q)) r.id,
        ];
        expect(await ids('كارف'), ['e1']);
        expect(await ids('معادي'), ['e1']);
        expect(await ids('١٢٥٠٫٥٠'), ['e1']);
        expect(await ids('cafe'), ['e2']);
        expect(await ids('كا'), ['e1']);
        expect(await ids('Ca'), ['e2']);
        for (final t in ['transactions_fts', 'transactions_fts_short']) {
          await db.customStatement(
            "INSERT INTO $t ($t) VALUES ('integrity-check')",
          );
        }
        await expectLater(
          OffsetLinksDao(
            db,
          ).insert(link('l1', expense: 'e2', source: 'i1', amountMinor: 901)),
          throwsA(
            isA<DbWriteException>().having(
              (e) => e.code,
              'code',
              DbWriteException.offsetExceedsExpense,
            ),
          ),
        );
        expect(
          await failureOf(
            db,
            "UPDATE transactions SET amount_minor = 1.5 WHERE id = 'e1'",
          ),
          DbWriteException.constraintCheck,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'T-018: v2 → v3 on this device: copy deleted, rows kept, schema = '
    'fresh v3, trigram candidates, secure-delete set and effective, m-1/m-2',
    () async {
      await storeKey(61);
      await makeV2File(world.mainFile);
      final result = await world.open();
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      try {
        expect(opened.migratedFrom, 2);
        expect(await userVersionOf(db), appSchemaVersion);
        expect(world.files.migrateTmp.existsSync(), isFalse);
        final fresh = AppDatabase(
          NativeDatabase.memory(),
          validateSchema: false,
        );
        final freshShape = await schemaShapeOf(fresh);
        await fresh.close();
        expect(sameSchemaShape(await schemaShapeOf(db), freshShape), isTrue);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );

        final txns = TransactionsDao(db);
        expect([for (final r in await txns.search('العزب')) r.id], ['e1']);

        // S-2 on this sqlite3mc: set, and a hard delete leaves no tokens.
        for (final t in ['transactions_fts', 'transactions_fts_short']) {
          expect(await secureDeleteOf(db, t), 1);
        }
        await txns.insert(txn('gone', merchant: 'qzxvjwk'));
        expect(
          await dataHolds(db, 'transactions_fts_short', 'qzxvjwk'),
          isTrue,
        );
        await db.customStatement("DELETE FROM transactions WHERE id = 'gone'");
        expect(
          await dataHolds(db, 'transactions_fts_short', 'qzxvjwk'),
          isFalse,
        );
        expect(await dataHolds(db, 'transactions_fts', 'zxv'), isFalse);

        final catalog = CatalogDao(db);
        await catalog.upsertMerchant(
          CatalogMerchantsCompanion.insert(
            id: const Value(1),
            canonical: 'El Ezaby',
            categoryCode: 'health',
            version: 1,
          ),
        );
        await catalog.upsertAlias(
          merchantId: 1,
          aliasNorm: 'ezaby',
          match: 'exact',
        );
        expect(
          [for (final a in await catalog.aliasCandidates('ezabi')) a.aliasNorm],
          ['ezaby'],
        );

        await expectLater(
          OffsetLinksDao(
            db,
          ).insert(link('l9', expense: 'nope', source: 'i1', amountMinor: 1)),
          throwsA(
            isA<DbWriteException>().having(
              (e) => e.code,
              'code',
              DbWriteException.constraintForeignKey,
            ),
          ),
        );
        expect(
          await failureOf(
            db,
            "UPDATE split_participants SET expense_txn_id = 'e2' "
            "WHERE id = 'p1'",
          ),
          DbWriteException.offsetParticipantMismatch,
        );
      } finally {
        await db.close();
      }
    },
  );

  test('D-50: key deleted → every file wiped (main last), new database with '
      'the restore notice', () async {
    await firstRun();
    for (final name in dbWipeOrder) {
      if (name == dbFileName ||
          name == migrateTmpFileName ||
          name == migratePartFileName) {
        continue;
      }
      File('${world.dbDir.path}/$name').writeAsBytesSync(const [7, 7, 7]);
    }
    await resetSlot();
    final result = await world.open(seed: 62);
    final opened = result as DbOpened<AppDatabase>;
    expect(opened.wipedOrphan, isTrue);
    expect(world.wipeLog, [for (final n in dbWipeOrder) 'db:$n', 'temp']);
    expect(await opened.db.restoreNoticeDue(), isTrue);
    await opened.db.close();
  });
}
