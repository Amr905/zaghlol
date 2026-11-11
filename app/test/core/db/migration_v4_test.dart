// T-019: the real v3 → v4 step (design note §1, §6, §8; database-schema §4)
// on an encrypted file through the app's opener: the pre-migration copy is
// made and deleted; every v2/v3 row survives (the four rebuilt tables row by
// row, the others by count); the migrated schema equals a fresh v4 and the
// committed v4 dump; the FK check is clean; alias trigram search and the FK
// cascades of the rebuilt parents still work; the new tables work and the
// tightened CHECKs are live. A v3 row that breaks a new CHECK, or a stray
// v4 table, fails the step and is rolled back byte for byte. Also: the
// frozen step equals the dumps. Keys and data synthetic.

import 'package:drift/drift.dart' show GeneratedDatabase, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/migrations/v4_financial_c.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'db_open_harness.dart';
import 'fake_next_database.dart';
import 'financial_fixtures.dart' show failureOf;
import 'migration_harness_test.dart' show settle;
import 'migration_v2_test.dart' show dumpShape, freshShape;
import 'migration_v3_test.dart' show dumpEntries;
import 'schema_v3_database.dart';

/// Every table of a v3 file (not FTS shadow tables).
const List<String> v3Tables = [
  'db_meta',
  'categories',
  'accounts',
  'account_balances',
  'raw_messages',
  'transactions',
  'transfer_pairs',
  'split_participants',
  'offset_links',
  'transactions_fts_src',
  'catalog_merchants',
  'catalog_aliases',
  'catalog_keywords',
  'catalog_meta',
  'merchant_rules',
  'budgets',
  'fired_alerts',
  'cycle_summaries',
  'recurring_items',
  'recurring_occurrences',
];

/// Every row of [table], in a stable order, as maps (values typed as
/// stored).
Future<List<Map<String, Object?>>> rowsOf(
  GeneratedDatabase db,
  String table,
) async => [
  for (final r
      in await db.customSelect('SELECT * FROM "$table" ORDER BY 1, 2').get())
    r.data,
];

/// Puts the bootstrap key (seed 61) in the store, then replaces the
/// database with a v3 file.
Future<void> prepareV3(DbWorld world, {List<String> extra = const []}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV3File(world.mainFile, extra: extra);
}

/// The rows of every v3 table of the v3 file in [world] (read through a
/// raw connection, before any migration).
Future<Map<String, List<Map<String, Object?>>>> snapshotV3(
  DbWorld world,
) async {
  final raw = V3Database(
    openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
  );
  try {
    return {for (final t in v3Tables) t: await rowsOf(raw, t)};
  } finally {
    await raw.close();
  }
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't019_mig');
  });

  tearDown(() => world.dispose());

  test('the frozen v3 → v4 step: rebuilds are exactly the v3 tables whose '
      'SQL changed, each with its v4 DDL under the temp name, all v4 '
      'columns and its v4 indexes; added objects are the new v4 entries in '
      'dump order without IF NOT EXISTS', () {
    final v3 = {for (final (n, s) in dumpEntries(3)) n: s};
    final v4 = dumpEntries(4);
    final v4ByName = {for (final (n, s) in v4) n: s};
    expect(v4ByName.keys.toSet().containsAll(v3.keys), isTrue);

    final changed = [
      for (final (name, sql) in v4)
        if (v3.containsKey(name) && v3[name] != sql) name,
    ];
    expect(changed, [
      'catalog_merchants',
      'catalog_keywords',
      'merchant_rules',
      'recurring_items',
    ]);
    expect([for (final r in v4Rebuilds) r.table], changed);

    for (final r in v4Rebuilds) {
      expect(
        r.createTemp,
        v4ByName[r.table]!.replaceFirst(
          'CREATE TABLE IF NOT EXISTS "${r.table}"',
          'CREATE TABLE "${r.temp}"',
        ),
      );
      expect(r.createTemp, isNot(contains('IF NOT EXISTS')));
      // Every column, as the table's DDL lists them.
      for (final col in r.columns) {
        expect(r.createTemp, contains('"$col"'));
      }
      final indexes = [
        for (final (_, sql) in v4)
          if (sql.startsWith('CREATE') &&
              sql.contains(' INDEX ') &&
              sql.contains(' ON ${r.table} '))
            sql,
      ];
      expect(r.indexes, indexes);
    }
    expect(
      {for (final r in v4Rebuilds) r.table: r.indexes.length},
      {
        'catalog_merchants': 0,
        'catalog_keywords': 0,
        'merchant_rules': 1,
        'recurring_items': 2,
      },
    );

    final added = [
      for (final (name, sql) in v4)
        if (!v3.containsKey(name))
          (
            name,
            sql.replaceFirst('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE'),
          ),
    ];
    expect(v4AddedObjects, added);
    expect(
      v4AddedObjects.every((o) => !o.$2.contains('IF NOT EXISTS')),
      isTrue,
    );
    expect(v4AddedObjects.length, 26);
  });

  test('the columns of each rebuilt table are the same in v3 and v4 '
      '(the copy moves every column by name)', () async {
    final db = V3Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    for (final r in v4Rebuilds) {
      final v3cols = [
        for (final row
            in await db.customSelect('PRAGMA table_info("${r.table}")').get())
          row.data['name'],
      ];
      expect(v3cols, r.columns, reason: r.table);
    }
  });

  test('the v3 helper equals the committed v3 dump', () async {
    final db = V3Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(
      sameSchemaShape(await schemaShapeOf(db), await dumpShape(3)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test('v3 → v4 through the opener: copy made then deleted, every row '
        'kept, schema = fresh v4 = dump, FK check clean, search and '
        'cascades work, new tables usable, CHECKs tightened ($mode)', () async {
      await prepareV3(world);
      final before = await snapshotV3(world);
      expect(before['recurring_items'], hasLength(2));
      expect(before['catalog_aliases'], hasLength(3));

      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      addTearDown(db.close);
      expect(opened.migratedFrom, 3);
      expect(db.attemptedUpgradeFrom, 3);
      expect(await userVersionOf(db), 4);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);
      expect(await metaValue(db, 'marker'), 'v3');

      // Every row of every v3 table, value for value (rebuilt or not).
      for (final t in v3Tables) {
        expect(await rowsOf(db, t), before[t], reason: t);
      }
      // The REAL 5.0 that v3 stored as INTEGER 5 is still an integer.
      expect(
        (await db
                .customSelect(
                  'SELECT typeof(due_day) AS t FROM recurring_items '
                  "WHERE id = 'ri1'",
                )
                .getSingle())
            .read<String>('t'),
        'integer',
      );

      final live = await schemaShapeOf(db);
      expect(sameSchemaShape(live, await freshShape()), isTrue);
      expect(sameSchemaShape(live, await dumpShape(4)), isTrue);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      // No temp table left behind.
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_schema WHERE name LIKE '%__v4'",
            )
            .get(),
        isEmpty,
      );

      // Search over v2 rows and v3 aliases still works.
      expect(
        [for (final r in await TransactionsDao(db).search('العزب')) r.id],
        ['e1'],
      );
      final catalog = CatalogDao(db);
      expect(
        [for (final a in await catalog.aliasCandidates('ezabi')) a.aliasNorm],
        ['ezaby'],
      );
      await db.customStatement(
        'INSERT INTO catalog_alias_fts '
        "(catalog_alias_fts) VALUES ('integrity-check')",
      );

      // The FK from catalog_aliases to the rebuilt catalog_merchants still
      // cascades, and so does recurring_occurrences → recurring_items.
      await db.customStatement('DELETE FROM catalog_merchants WHERE id = 77');
      expect(
        await db
            .customSelect(
              'SELECT alias_norm FROM catalog_aliases ORDER BY alias_norm',
            )
            .get()
            .then((rs) => [for (final r in rs) r.read<String>('alias_norm')]),
        ['koshary synthetic'],
      );
      expect(await catalog.aliasCandidates('ezabi'), isEmpty);
      await db.customStatement("DELETE FROM recurring_items WHERE id = 'ri1'");
      expect(
        await db.customSelect('SELECT * FROM recurring_occurrences').get(),
        isEmpty,
      );
      // A rule's category is still a real FK.
      expect(
        await failureOf(
          db,
          "UPDATE merchant_rules SET category_id = 'nope' WHERE id = 'r1'",
        ),
        DbWriteException.constraintForeignKey,
      );

      // The tightened CHECKs are live on the rebuilt tables.
      expect(
        await failureOf(
          db,
          "UPDATE recurring_items SET reminder_days = 1.5 WHERE id = 'ri2'",
        ),
        DbWriteException.constraintCheck,
      );
      expect(
        await failureOf(
          db,
          "UPDATE catalog_keywords SET keyword_norm = 'a' || char(0) || 'b' "
          "WHERE lang = 'en'",
        ),
        DbWriteException.constraintCheck,
      );

      // New tables work.
      final settings = SettingsDao(db);
      await settings.write('theme', 'dark', at: 1);
      expect(await settings.read('theme'), 'dark');
      expect(
        await failureOf(
          db,
          'INSERT INTO assets (id, type, name, created_at) '
          "VALUES ('x', 'gold', 'g', 0)",
        ),
        DbWriteException.constraintCheck,
      );
    });
  }

  test('reopening a migrated v3 file is a plain open', () async {
    await prepareV3(world);
    await openedDb(await world.open(executor: foregroundExecutor)).close();
    final again = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(again.close);
    expect(again.attemptedUpgradeFrom, isNull);
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  for (final (what, extra) in [
    (
      'a REAL 1.5 in a column v4 makes integer-only',
      ["UPDATE recurring_items SET due_day = 1.5 WHERE id = 'ri1'"],
    ),
    (
      'a NUL in a catalog keyword',
      [
        'INSERT INTO catalog_keywords (keyword_norm, lang, category_code, '
            "weight) VALUES ('a' || char(0) || 'b', 'ar', 'health', 1)",
      ],
    ),
    (
      'a stray v3 "assets" table',
      ['CREATE TABLE assets (id TEXT PRIMARY KEY, junk INTEGER)'],
    ),
    (
      'a stray table with the rebuild temp name',
      ['CREATE TABLE "merchant_rules__v4" (x INTEGER)'],
    ),
  ]) {
    test('a failing v3 → v4 step ($what) is DB_MIGRATION_FAILED(restored): '
        'every file byte-identical, still v3, rows intact', () async {
      await prepareV3(world, extra: extra);
      final rowsBefore = await snapshotV3(world);
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 3);
      expect(failed.toVersion, 4);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final raw = V3Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 3);
      for (final t in v3Tables) {
        expect(await rowsOf(raw, t), rowsBefore[t], reason: t);
      }
    });
  }

  test(
    'v3 → next (FakeNextDatabase) runs the real v3 → v4 step first',
    () async {
      await prepareV3(world);
      final result = await world.openWith(
        fakeNextFactory(),
        FakeNextDatabase.version,
      );
      final opened = result as DbOpened<FakeNextDatabase>;
      addTearDown(opened.db.close);
      expect(opened.migratedFrom, 3);
      expect(await userVersionOf(opened.db), FakeNextDatabase.version);
      expect(
        sameSchemaShape(await schemaShapeOf(opened.db), await freshShape()),
        isTrue,
      );
      expect(await rowsOf(opened.db, 'recurring_items'), hasLength(2));
    },
  );
}
