// T-017: the real v1 → v2 step (design note §1, §9; database-schema §4) on
// an encrypted file through the app's opener: the pre-migration copy is made
// and deleted, `db_meta` survives, the migrated schema equals a fresh v2 and
// the committed v2 dump (CHECKs included), the new tables work, and a failing
// step is rolled back byte for byte. Also: the frozen step SQL equals the
// dump, and version pairs without a path are refused. Keys synthetic.
// T-018: the app is at v3 now, so a v1 file runs v1 → v2 → v3 through the
// opener; v1 + the frozen v2 statements must still equal the v2 dump. The
// v2 → v3 step itself is tested in migration_v3_test.dart.

import 'package:drift/drift.dart' show Migrator, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/migrations/v2_financial_a.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'app_database_test.dart' show dumpSql;
import 'db_open_harness.dart';
import 'fake_next_database.dart';
import 'financial_fixtures.dart';
import 'migration_harness_test.dart' show settle;
import 'schema_v1_database.dart';
import 'sqlite3mc_contract.dart' show ContractDb;

/// Puts the bootstrap key (seed 61) in the store, then replaces the
/// database with a v1 file holding [meta] (and [extra] statements).
Future<void> prepareV1(
  DbWorld world, {
  Map<String, String> meta = const {'marker': 'v1', 'other': 'kept'},
  List<String> extra = const [],
}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV1File(world.mainFile, meta: meta, extra: extra);
}

Future<List<String>> freshShape() async {
  final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
  try {
    return await schemaShapeOf(db);
  } finally {
    await db.close();
  }
}

Future<List<String>> dumpShape(int version) async {
  final db = ContractDb(NativeDatabase.memory());
  try {
    for (final sql in dumpSql(version)) {
      await db.customStatement(sql);
    }
    return await schemaShapeOf(db);
  } finally {
    await db.close();
  }
}

/// Exposes the protected step runner.
final class _Probe extends AppDatabase {
  _Probe() : super(NativeDatabase.memory(), validateSchema: false);

  Future<void> run(int from, int to) => upgradeSteps(Migrator(this), from, to);
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't017_mig');
  });

  tearDown(() => world.dispose());

  test('the v1 helper is the committed v1 dump', () {
    expect(v1Sql, dumpSql(1));
  });

  test('the frozen v1 → v2 statements are the v2 dump minus db_meta, in '
      'order, without IF NOT EXISTS', () {
    final fromDump = [
      for (final sql in dumpSql(2))
        if (!sql.contains('"db_meta"'))
          sql
              .replaceFirst('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE')
              .replaceFirst(
                'CREATE VIRTUAL TABLE IF NOT EXISTS',
                'CREATE VIRTUAL TABLE',
              ),
    ];
    expect([for (final (_, sql) in v2AddedObjects) sql], fromDump);
    expect(
      v2AddedObjects.every((o) => !o.$2.contains('IF NOT EXISTS')),
      isTrue,
    );
  });

  test('v1 + the frozen v2 statements equal the committed v2 dump, CHECKs '
      'included', () async {
    final db = ContractDb(NativeDatabase.memory());
    addTearDown(db.close);
    for (final sql in [...v1Sql, for (final (_, s) in v2AddedObjects) s]) {
      await db.customStatement(sql);
    }
    final shape = await schemaShapeOf(db);
    expect(shape.where((l) => l.startsWith('check ')), isNotEmpty);
    expect(sameSchemaShape(shape, await dumpShape(2)), isTrue);
  });

  test('a fresh database equals the latest committed dump', () async {
    expect(
      sameSchemaShape(await freshShape(), await dumpShape(appSchemaVersion)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test(
      'v1 → latest through the opener: copy made then deleted, db_meta '
      'kept, schema = fresh = dump, FK check clean, v2 tables work ($mode)',
      () async {
        await prepareV1(world);
        final result = await world.open(
          executor: background ? defaultDbExecutor : foregroundExecutor,
        );
        final opened = result as DbOpened<AppDatabase>;
        final db = opened.db;
        addTearDown(db.close);
        expect(opened.migratedFrom, 1);
        expect(opened.diagCode, 'DB_MIGRATED');
        expect(db.attemptedUpgradeFrom, 1);
        expect(await userVersionOf(db), appSchemaVersion);
        expect(world.files.migrateTmp.existsSync(), isFalse);
        expect(world.files.migratePart.existsSync(), isFalse);
        expect(await metaValue(db, 'marker'), 'v1');
        expect(await metaValue(db, 'other'), 'kept');

        final live = await schemaShapeOf(db);
        expect(sameSchemaShape(live, await freshShape()), isTrue);
        expect(
          sameSchemaShape(live, await dumpShape(appSchemaVersion)),
          isTrue,
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await db.customSelect('PRAGMA foreign_keys').getSingle())
              .data
              .values
              .single,
          1,
        );

        // The new objects work on the migrated file: FTS triggers, offset
        // triggers, CHECKs.
        await AccountsDao(db).insert(account('acc1'));
        final txns = TransactionsDao(db);
        await txns.insert(
          txn('e1', merchant: 'صيدلية العزبي', amountMinor: 1000),
        );
        await txns.insert(txn('i1', direction: 'income', amountMinor: 5000));
        expect([for (final r in await txns.search('العزب')) r.id], ['e1']);
        expect([for (final r in await txns.search('صي')) r.id], ['e1']);
        await expectLater(
          OffsetLinksDao(
            db,
          ).insert(link('l1', expense: 'e1', source: 'i1', amountMinor: 1001)),
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
      },
    );
  }

  test(
    'reopening the migrated file is a plain open (no copy, no upgrade)',
    () async {
      await prepareV1(world);
      await openedDb(await world.open(executor: foregroundExecutor)).close();
      final again = openedDb(await world.open(executor: foregroundExecutor));
      addTearDown(again.close);
      expect(again.attemptedUpgradeFrom, isNull);
      expect(world.files.migrateTmp.existsSync(), isFalse);
    },
  );

  test(
    'a failing v1 → v2 step (a stray v1 "accounts" table) is '
    'DB_MIGRATION_FAILED(restored): every file byte-identical, still v1',
    () async {
      await prepareV1(
        world,
        extra: ['CREATE TABLE accounts (id TEXT PRIMARY KEY, junk INTEGER)'],
      );
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 1);
      expect(failed.toVersion, appSchemaVersion);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final raw = V1Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 1);
      expect(await metaValue(raw, 'marker'), 'v1');
      final tables = await raw
          .customSelect(
            "SELECT name FROM sqlite_schema WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();
      expect(
        [for (final t in tables) t.read<String>('name')],
        ['accounts', 'db_meta'],
      );
    },
  );

  test(
    'v1 → next (FakeNextDatabase) runs the real v1 → v2 → v3 steps first',
    () async {
      await prepareV1(world);
      final result = await world.openWith(
        fakeNextFactory(),
        FakeNextDatabase.version,
      );
      final opened = result as DbOpened<FakeNextDatabase>;
      addTearDown(opened.db.close);
      expect(opened.migratedFrom, 1);
      expect(await userVersionOf(opened.db), FakeNextDatabase.version);
      expect(await metaValue(opened.db, 'fake_next'), '1');
      expect(
        sameSchemaShape(await schemaShapeOf(opened.db), await freshShape()),
        isTrue,
      );
    },
  );

  test(
    'version pairs without a path are refused before anything runs',
    () async {
      final probe = _Probe();
      addTearDown(probe.close);
      const v = appSchemaVersion;
      for (final (from, to) in [
        (0, v),
        (v, v),
        (1, v + 1),
        (v, 1),
        (1, 1),
        (1, 2),
        (2, 2),
      ]) {
        await expectLater(
          probe.run(from, to),
          throwsA(
            isA<DbMigrationException>().having(
              (e) => e.code,
              'code',
              DbMigrationException.noMigrationPath,
            ),
          ),
          reason: '$from → $to',
        );
      }
    },
  );
}
