// T-266: the real v5 → v6 step on an encrypted file through the app's opener:
// the pre-migration copy is made and deleted; every v5 row survives
// (accounts row by row with `linked_account_id` NULL; the others by value);
// the migrated schema equals a fresh v6 and the committed v6 dump; the FK
// check is clean; the new column's FK and CHECK hold. A failing step is
// rolled back byte for byte. Also: the frozen step equals the dumps. Keys
// and data synthetic.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/migrations/v6_linked_account.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'db_open_harness.dart';
import 'financial_fixtures.dart' show failureOf;
import 'migration_harness_test.dart' show settle;
import 'migration_v2_test.dart' show dumpShape, freshShape;
import 'migration_v3_test.dart' show dumpEntries;
import 'migration_v4_test.dart' show rowsOf;
import 'migration_v5_test.dart' show v4SampleTables;
import 'schema_v5_database.dart';

/// Every table of a v5 file the samples fill.
const List<String> v5SampleTables = [...v4SampleTables, 'recurring_dismissals'];

Future<void> prepareV5(DbWorld world, {List<String> extra = const []}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV5File(world.mainFile, extra: extra);
}

Future<Map<String, List<Map<String, Object?>>>> snapshotV5(
  DbWorld world,
) async {
  final raw = V5Database(
    openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
  );
  try {
    return {for (final t in v5SampleTables) t: await rowsOf(raw, t)};
  } finally {
    await raw.close();
  }
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't266_mig');
  });

  tearDown(() => world.dispose());

  test('the frozen v5 → v6 step: the one changed table is accounts, whose v6 '
      'SQL is the v5 SQL plus exactly the added column; the added object is '
      'the new index, without IF NOT EXISTS', () {
    final v5 = {for (final (n, s) in dumpEntries(5)) n: s};
    final v6 = dumpEntries(6);
    final v6ByName = {for (final (n, s) in v6) n: s};
    expect(v6ByName.keys.toSet().containsAll(v5.keys), isTrue);
    final changed = [
      for (final (name, sql) in v6)
        if (v5.containsKey(name) && v5[name] != sql) name,
    ];
    expect(changed, ['accounts']);

    const prefix = 'ALTER TABLE "accounts" ADD COLUMN ';
    expect(v6AddLinkedAccountColumn, startsWith(prefix));
    final column = v6AddLinkedAccountColumn.substring(prefix.length);
    final before = v5['accounts']!;
    expect(before, endsWith(');'));
    expect(
      v6ByName['accounts'],
      '${before.substring(0, before.length - 2)}, $column);',
    );

    expect(v6AddedObjects, [
      for (final (name, sql) in v6)
        if (!v5.containsKey(name)) (name, sql),
    ]);
    expect([for (final (n, _) in v6AddedObjects) n], ['ix_accounts_linked']);
    expect(v6AddedObjects.single.$2, isNot(contains('IF NOT EXISTS')));
  });

  test('the v5 helper equals the committed v5 dump', () async {
    final db = V5Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(
      sameSchemaShape(await schemaShapeOf(db), await dumpShape(5)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test('v5 → v6 through the opener: copy made then deleted, every row '
        'kept, linked_account_id NULL, schema = fresh v6 = dump, FK check '
        'clean, the new FK and CHECK hold ($mode)', () async {
      await prepareV5(world);
      final before = await snapshotV5(world);
      expect(before['accounts'], hasLength(4));

      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      addTearDown(db.close);
      expect(opened.migratedFrom, 5);
      expect(db.attemptedUpgradeFrom, 5);
      expect(await userVersionOf(db), 6);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);

      for (final t in v5SampleTables) {
        var rows = await rowsOf(db, t);
        if (t == 'accounts') {
          expect([
            for (final r in rows) r['linked_account_id'],
          ], everyElement(isNull));
          rows = [
            for (final r in rows) {...r}..remove('linked_account_id'),
          ];
        }
        expect(rows, before[t], reason: t);
      }

      final live = await schemaShapeOf(db);
      expect(sameSchemaShape(live, await freshShape()), isTrue);
      expect(sameSchemaShape(live, await dumpShape(6)), isTrue);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      // A debit card links to an account.
      expect(
        await failureOf(
          db,
          "UPDATE accounts SET linked_account_id = 'acc5' WHERE id = 'card5'",
        ),
        isNull,
      );
      // ... never to a missing account, never to itself, and a non-debit
      // account can't be linked.
      expect(
        await failureOf(
          db,
          "UPDATE accounts SET linked_account_id = 'nope' WHERE id = 'acc1'",
        ),
        DbWriteException.constraintForeignKey,
      );
      expect(
        await failureOf(
          db,
          "UPDATE accounts SET linked_account_id = 'acc1' WHERE id = 'acc1'",
        ),
        DbWriteException.constraintCheck,
      );
      expect(
        await failureOf(
          db,
          "UPDATE accounts SET linked_account_id = 'acc1' WHERE id = 'wal5'",
        ),
        DbWriteException.constraintCheck,
      );
      // A linked card can't become a credit card while linked.
      expect(
        await failureOf(
          db,
          "UPDATE accounts SET kind = 'credit' WHERE id = 'card5'",
        ),
        DbWriteException.constraintCheck,
      );
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_schema WHERE name = 'ix_accounts_linked'",
            )
            .get(),
        hasLength(1),
      );
    });
  }

  test('reopening a migrated v5 file is a plain open', () async {
    await prepareV5(world);
    await openedDb(await world.open(executor: foregroundExecutor)).close();
    final again = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(again.close);
    expect(again.attemptedUpgradeFrom, isNull);
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  for (final (what, extra) in [
    (
      'a stray "ix_accounts_linked" index',
      ['CREATE INDEX ix_accounts_linked ON accounts (label)'],
    ),
    (
      'a stray accounts column with the new name',
      ['ALTER TABLE accounts ADD COLUMN linked_account_id TEXT'],
    ),
  ]) {
    test('a failing v5 → v6 step ($what) is DB_MIGRATION_FAILED(restored): '
        'every file byte-identical, still v5, rows intact', () async {
      await prepareV5(world, extra: extra);
      final rowsBefore = await snapshotV5(world);
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 5);
      expect(failed.toVersion, 6);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final raw = V5Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 5);
      for (final t in v5SampleTables) {
        expect(await rowsOf(raw, t), rowsBefore[t], reason: t);
      }
    });
  }

  test('the opener never sees a v6 file as needing a migration', () async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(db.close);
    expect(await userVersionOf(db), appSchemaVersion);
    expect(db.attemptedUpgradeFrom, isNull);
  });
}
