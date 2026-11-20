// T-196: the real v4 → v5 step on an encrypted file through the app's opener:
// the pre-migration copy is made and deleted; every v4 row survives (the
// rebuilt recurring_items row by row, `auto_added_at` NULL; the others by
// value); the migrated schema equals a fresh v5 and the committed v5 dump;
// the FK check is clean; the cascade from items to occurrences still works;
// the two new cadences and the dismissals table work. A failing step is
// rolled back byte for byte. Also: the frozen step equals the dumps. Keys
// and data synthetic.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/migrations/v5_recurring_cadence.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'db_open_harness.dart';
import 'financial_fixtures.dart' show failureOf;
import 'migration_harness_test.dart' show settle;
import 'migration_v2_test.dart' show dumpShape, freshShape;
import 'migration_v3_test.dart' show dumpEntries;
import 'migration_v4_test.dart' show rowsOf, v3Tables;
import 'schema_v4_database.dart';

/// Every table of a v4 file the step keeps as is or rebuilds (not FTS shadow
/// tables), plus the v4 additions the samples fill.
const List<String> v4SampleTables = [
  ...v3Tables,
  'assets',
  'settings',
  'review_items',
];

Future<void> prepareV4(DbWorld world, {List<String> extra = const []}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV4File(world.mainFile, extra: extra);
}

Future<Map<String, List<Map<String, Object?>>>> snapshotV4(
  DbWorld world,
) async {
  final raw = V4Database(
    openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
  );
  try {
    return {for (final t in v4SampleTables) t: await rowsOf(raw, t)};
  } finally {
    await raw.close();
  }
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't196_mig');
  });

  tearDown(() => world.dispose());

  test('the frozen v4 → v5 step: the one rebuild is the v4 table whose SQL '
      'changed, with its v5 DDL under the temp name, the v4 columns and its '
      'indexes; the added object is the new v5 entry, without IF NOT '
      'EXISTS', () {
    final v4 = {for (final (n, s) in dumpEntries(4)) n: s};
    final v5 = dumpEntries(5);
    final v5ByName = {for (final (n, s) in v5) n: s};
    expect(v5ByName.keys.toSet().containsAll(v4.keys), isTrue);

    final changed = [
      for (final (name, sql) in v5)
        if (v4.containsKey(name) && v4[name] != sql) name,
    ];
    expect(changed, ['recurring_items']);
    const r = v5RecurringRebuild;
    expect(r.table, 'recurring_items');
    expect(
      r.createTemp,
      v5ByName['recurring_items']!.replaceFirst(
        'CREATE TABLE IF NOT EXISTS "recurring_items"',
        'CREATE TABLE "recurring_items__v5"',
      ),
    );
    expect(r.createTemp, isNot(contains('IF NOT EXISTS')));
    expect(r.createTemp, contains("'quarterly', 'semi_annual'"));
    expect(r.createTemp, contains('"auto_added_at"'));
    expect(r.indexes, [
      for (final (_, sql) in v5)
        if (sql.startsWith('CREATE') &&
            sql.contains(' INDEX ') &&
            sql.contains(' ON recurring_items '))
          sql,
    ]);
    expect(r.indexes, hasLength(2));

    expect(v5AddedObjects, [
      for (final (name, sql) in v5)
        if (!v4.containsKey(name))
          (
            name,
            sql.replaceFirst('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE'),
          ),
    ]);
    expect([for (final (n, _) in v5AddedObjects) n], ['recurring_dismissals']);
    expect(v5AddedObjects.single.$2, isNot(contains('IF NOT EXISTS')));
  });

  test('the columns copied are the v4 columns; v5 adds exactly '
      '`auto_added_at`', () async {
    final db = V4Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    final v4cols = [
      for (final row
          in await db
              .customSelect('PRAGMA table_info("recurring_items")')
              .get())
        row.data['name'],
    ];
    expect(v4cols, v5RecurringRebuild.columns);
    final fresh = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(fresh.close);
    final v5cols = [
      for (final row
          in await fresh
              .customSelect('PRAGMA table_info("recurring_items")')
              .get())
        row.data['name'],
    ];
    expect(v5cols, [...v5RecurringRebuild.columns, 'auto_added_at']);
  });

  test('the v4 helper equals the committed v4 dump', () async {
    final db = V4Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(
      sameSchemaShape(await schemaShapeOf(db), await dumpShape(4)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test('v4 → v5 through the opener: copy made then deleted, every row '
        'kept, auto_added_at NULL, schema = fresh v5 = dump, FK check clean, '
        'cascade works, new cadences and dismissals usable ($mode)', () async {
      await prepareV4(world);
      final before = await snapshotV4(world);
      expect(before['recurring_items'], hasLength(6));

      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      addTearDown(db.close);
      expect(opened.migratedFrom, 4);
      expect(db.attemptedUpgradeFrom, 4);
      expect(await userVersionOf(db), 5);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);
      expect(await metaValue(db, 'marker'), 'v3');

      for (final t in v4SampleTables) {
        var rows = await rowsOf(db, t);
        if (t == 'recurring_items') {
          expect([
            for (final r in rows) r['auto_added_at'],
          ], everyElement(isNull));
          rows = [
            for (final r in rows) {...r}..remove('auto_added_at'),
          ];
        }
        expect(rows, before[t], reason: t);
      }
      // The old cadences are still there, value for value.
      expect(
        {
          for (final r in await rowsOf(db, 'recurring_items'))
            r['id']: r['cadence'],
        },
        {
          'ri1': 'monthly',
          'ri2': 'custom_days',
          'rm': 'monthly',
          'ry': 'yearly',
          'rw': 'weekly',
          'rc': 'monthly',
        },
      );

      final live = await schemaShapeOf(db);
      expect(sameSchemaShape(live, await freshShape()), isTrue);
      expect(sameSchemaShape(live, await dumpShape(5)), isTrue);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_schema WHERE name LIKE '%__v5'",
            )
            .get(),
        isEmpty,
      );

      // The rebuilt table's indexes exist again.
      expect(
        {
          for (final r
              in await db
                  .customSelect(
                    'SELECT name FROM sqlite_schema WHERE type = \'index\' '
                    "AND tbl_name = 'recurring_items' AND name LIKE 'ix_%'",
                  )
                  .get())
            r.read<String>('name'),
        },
        {'ix_recurring_due', 'ix_recurring_account'},
      );

      // The FK from occurrences to the rebuilt items still cascades.
      expect(
        await db.customSelect('SELECT * FROM recurring_occurrences').get(),
        hasLength(4),
      );
      await db.customStatement("DELETE FROM recurring_items WHERE id = 'rm'");
      expect(
        [
          for (final r
              in await db
                  .customSelect('SELECT item_id FROM recurring_occurrences')
                  .get())
            r.read<String>('item_id'),
        ]..sort(),
        ['ri1', 'ri1', 'ry'],
      );
      // ... and the FK to accounts is still real.
      expect(
        await failureOf(
          db,
          "UPDATE recurring_items SET account_id = 'nope' WHERE id = 'ry'",
        ),
        DbWriteException.constraintForeignKey,
      );

      // The two new cadences, and only those, are accepted.
      Future<String?> addCadence(String id, String cadence) => failureOf(
        db,
        'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
        "currency, cadence, created_at) VALUES ('$id', 'subscription', "
        "'active', 'x', 100, 'EGP', '$cadence', 1)",
      );
      expect(await addCadence('n1', 'quarterly'), isNull);
      expect(await addCadence('n2', 'semi_annual'), isNull);
      expect(await addCadence('n3', 'yearly'), isNull);
      expect(
        await addCadence('n4', 'every_3_months'),
        DbWriteException.constraintCheck,
      );
      expect(
        await failureOf(
          db,
          'UPDATE recurring_items SET auto_added_at = 1.5 '
          "WHERE id = 'n1'",
        ),
        DbWriteException.constraintCheck,
      );
      // The earlier tightenings survived the rebuild.
      expect(
        await failureOf(
          db,
          "UPDATE recurring_items SET reminder_days = 1.5 WHERE id = 'ry'",
        ),
        DbWriteException.constraintCheck,
      );

      // The dismissals table works through its DAO and is idempotent.
      final dao = RecurringDao(db);
      await dao.rememberDismissal('streamco|acc1|EGP', at: 10);
      await dao.rememberDismissal('streamco|acc1|EGP', at: 20);
      expect(await dao.dismissalKeys(), {'streamco|acc1|EGP'});
      expect(
        (await db
                .customSelect('SELECT dismissed_at FROM recurring_dismissals')
                .getSingle())
            .read<int>('dismissed_at'),
        10,
      );
    });
  }

  test('reopening a migrated v4 file is a plain open', () async {
    await prepareV4(world);
    await openedDb(await world.open(executor: foregroundExecutor)).close();
    final again = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(again.close);
    expect(again.attemptedUpgradeFrom, isNull);
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  for (final (what, extra) in [
    (
      'a stray "recurring_dismissals" table',
      ['CREATE TABLE recurring_dismissals (x INTEGER)'],
    ),
    (
      'a stray table with the rebuild temp name',
      ['CREATE TABLE "recurring_items__v5" (x INTEGER)'],
    ),
  ]) {
    test('a failing v4 → v5 step ($what) is DB_MIGRATION_FAILED(restored): '
        'every file byte-identical, still v4, rows intact', () async {
      await prepareV4(world, extra: extra);
      final rowsBefore = await snapshotV4(world);
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 4);
      expect(failed.toVersion, 5);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final raw = V4Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 4);
      for (final t in v4SampleTables) {
        expect(await rowsOf(raw, t), rowsBefore[t], reason: t);
      }
    });
  }

  test('the opener never sees a v5 file as needing a migration', () async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(db.close);
    expect(await userVersionOf(db), appSchemaVersion);
    expect(db.attemptedUpgradeFrom, isNull);
  });
}
