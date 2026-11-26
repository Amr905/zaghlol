// T-356: the real v6 → v7 step on an encrypted file through the app's opener
// (AC1, AC2): the pre-migration copy is made and deleted; every v6 row of
// every sample table is byte-identical afterwards (rowid and `quote()` of
// every column, so type and value), in particular every transaction's
// category id and source, every merchant rule and every outbox row; the
// migrated schema equals a fresh v7 and the committed v7 dump; the FK and
// integrity checks are clean; the re-created view and triggers work (search
// still finds old rows and indexes new ones, offset limits still abort); the
// new tables are empty and usable, `ai` and the LLM outbox kinds are
// accepted. A failing step is rolled back byte for byte. Also: the frozen
// step equals the dumps. Keys and data synthetic.

import 'package:drift/drift.dart'
    show GeneratedDatabase, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/migrations/v7_llm_categorise.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'db_open_harness.dart';
import 'financial_fixtures.dart' show failureOf;
import 'migration_harness_test.dart' show settle;
import 'migration_v2_test.dart' show dumpShape, freshShape;
import 'migration_v3_test.dart' show dumpEntries;
import 'migration_v6_test.dart' show v5SampleTables;
import 'schema_v6_database.dart';

/// Every table of a v6 file the samples fill.
final List<String> v6SampleTables = {...v5SampleTables, 'outbox'}.toList();

/// A synthetic time after the samples (epoch ms).
const int _t1 = 1793600000000;

Future<void> prepareV6(DbWorld world, {List<String> extra = const []}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV6File(world.mainFile, extra: extra);
}

/// The column names of [table], in order.
Future<List<String>> columnsOf(GeneratedDatabase db, String table) async => [
  for (final r in await db.customSelect('PRAGMA table_info("$table")').get())
    r.read<String>('name'),
];

/// Every row of [table] as text that is equal only when the stored bytes
/// are: the rowid, then `quote()` of each of [columns] (type and value).
Future<List<String>> exactRows(
  GeneratedDatabase db,
  String table,
  List<String> columns,
) async {
  final cols = ['rowid', for (final c in columns) 'quote("$c")'].join(', ');
  return [
    for (final r
        in await db
            .customSelect('SELECT $cols FROM "$table" ORDER BY rowid')
            .get())
      r.data.values.join('|'),
  ];
}

/// Columns and exact rows of every sample table in the v6 file.
typedef V6Snapshot = ({
  Map<String, List<String>> columns,
  Map<String, List<String>> rows,
});

Future<V6Snapshot> snapshotV6(DbWorld world) async {
  final raw = V6Database(
    openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
  );
  try {
    final columns = <String, List<String>>{};
    final rows = <String, List<String>>{};
    for (final t in v6SampleTables) {
      columns[t] = await columnsOf(raw, t);
      rows[t] = await exactRows(raw, t, columns[t]!);
    }
    return (columns: columns, rows: rows);
  } finally {
    await raw.close();
  }
}

/// A view or trigger (not on `transactions` itself) whose SQL reads the
/// `transactions` table.
final RegExp _readsTransactions = RegExp(r'\btransactions\b(?!_)');

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't356_mig');
  });

  tearDown(() => world.dispose());

  group('the frozen v6 → v7 step equals the dumps', () {
    final v6 = {for (final (n, s) in dumpEntries(6)) n: s};
    final v7 = dumpEntries(7);
    final v7ByName = {for (final (n, s) in v7) n: s};

    test('the changed objects are exactly the rebuilt tables, each temp DDL '
        'is the v7 DDL, each index list is the table\'s v7 indexes', () {
      expect(v7ByName.keys.toSet().containsAll(v6.keys), isTrue);
      final changed = [
        for (final (name, sql) in v7)
          if (v6.containsKey(name) && v6[name] != sql) name,
      ];
      expect(changed, [for (final r in v7Rebuilds) r.table]);
      expect(changed, ['transactions', 'outbox']);
      for (final r in v7Rebuilds) {
        expect(
          r.createTemp,
          v7ByName[r.table]!.replaceFirst(
            'CREATE TABLE IF NOT EXISTS "${r.table}"',
            'CREATE TABLE "${r.temp}"',
          ),
          reason: r.table,
        );
        expect(r.createTemp, startsWith('CREATE TABLE "${r.table}__v7" ('));
        expect(r.indexes, [
          for (final (_, sql) in v7)
            if (sql.startsWith('CREATE INDEX') &&
                sql.contains(' ON ${r.table} '))
              sql,
        ], reason: r.table);
      }
      // The widened CHECKs.
      expect(
        v7Rebuilds.first.createTemp,
        contains(
          "category_source IN ('user', 'user_rule', 'catalog', "
          "'heuristic', 'none', 'ai')",
        ),
      );
      expect(
        v7Rebuilds.last.createTemp,
        contains(
          "kind IN ('contribution', 'bank_request', 'purchase_verify', "
          "'llm_cat_confirmation', 'llm_cat_correction')",
        ),
      );
    });

    test(
      'the dropped dependents are every v6 view or trigger on another '
      'table that reads transactions; the restored objects are those plus '
      'every trigger on transactions, unchanged from v6, in v7 dump order',
      () {
        bool isViewOrTrigger(String sql) =>
            sql.startsWith('CREATE VIEW') || sql.startsWith('CREATE TRIGGER');
        bool onTransactions(String sql) =>
            RegExp(r' ON transactions\b(?!_)').hasMatch(sql);
        final dependents = [
          for (final (name, sql) in dumpEntries(6))
            if (isViewOrTrigger(sql) &&
                !onTransactions(sql) &&
                _readsTransactions.hasMatch(sql))
              (sql.startsWith('CREATE VIEW') ? 'VIEW' : 'TRIGGER', name),
        ];
        expect(v7DroppedDependents, dependents);
        expect(v7DroppedDependents, [
          ('TRIGGER', 'trg_offset_links_bi'),
          ('TRIGGER', 'trg_offset_links_bu'),
          ('VIEW', 'transactions_fts_row'),
        ]);
        final droppedNames = {for (final (_, n) in v7DroppedDependents) n};
        expect(v7RestoredObjects, [
          for (final (name, sql) in v7)
            if (droppedNames.contains(name) ||
                (sql.startsWith('CREATE TRIGGER') && onTransactions(sql)))
              (name, sql),
        ]);
        for (final (name, sql) in v7RestoredObjects) {
          expect(sql, v6[name], reason: '$name is unchanged from v6');
        }
      },
    );

    test('the added objects are the new tables, without IF NOT EXISTS', () {
      expect(v7AddedObjects, [
        for (final (name, sql) in v7)
          if (!v6.containsKey(name))
            (
              name,
              sql.replaceFirst('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE'),
            ),
      ]);
      expect(
        [for (final (n, _) in v7AddedObjects) n],
        ['ai_merchant_suggestions', 'llm_cat_queue'],
      );
      for (final (_, sql) in v7AddedObjects) {
        expect(sql, isNot(contains('IF NOT EXISTS')));
      }
    });

    test('each rebuild copies every v6 column, and v7 has no other', () async {
      final db6 = V6Database(NativeDatabase.memory(), populated: false);
      addTearDown(db6.close);
      final db7 = AppDatabase(NativeDatabase.memory(), validateSchema: false);
      addTearDown(db7.close);
      for (final r in v7Rebuilds) {
        expect(r.columns, await columnsOf(db6, r.table), reason: r.table);
        expect(r.columns, await columnsOf(db7, r.table), reason: r.table);
      }
    });
  });

  test('the v6 helper equals the committed v6 dump', () async {
    final db = V6Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(
      sameSchemaShape(await schemaShapeOf(db), await dumpShape(6)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test('AC1/AC2: v6 → v7 through the opener: copy made then deleted, every '
        'v6 row byte-identical (rowid, type, value), schema = fresh v7 = '
        'dump, FK and integrity checks clean ($mode)', () async {
      await prepareV6(world);
      final before = await snapshotV6(world);
      // The samples cover what AC2 names.
      expect(before.rows['transactions'], hasLength(greaterThan(8)));
      expect(before.rows['merchant_rules'], hasLength(greaterThan(1)));
      expect(before.rows['outbox'], hasLength(3));
      expect(before.rows['transactions_fts_src'], isNotEmpty);

      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      addTearDown(db.close);
      expect(opened.migratedFrom, 6);
      expect(db.attemptedUpgradeFrom, 6);
      expect(await userVersionOf(db), 7);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);

      for (final t in v6SampleTables) {
        expect(await columnsOf(db, t), before.columns[t], reason: t);
        expect(
          await exactRows(db, t, before.columns[t]!),
          before.rows[t],
          reason: t,
        );
      }
      // Spelled out for AC2: category id and source of every transaction.
      final sources = await db
          .customSelect(
            'SELECT category_source AS s, count(*) AS n FROM transactions '
            'GROUP BY 1 ORDER BY 1',
          )
          .get();
      expect(
        {for (final r in sources) r.read<String>('s')},
        {'catalog', 'heuristic', 'none', 'user', 'user_rule'},
      );

      final live = await schemaShapeOf(db);
      expect(sameSchemaShape(live, await freshShape()), isTrue);
      expect(sameSchemaShape(live, await dumpShape(7)), isTrue);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok',
      );

      // The new tables: empty, then usable.
      for (final t in ['ai_merchant_suggestions', 'llm_cat_queue']) {
        final n = await db
            .customSelect('SELECT count(*) AS n FROM "$t"')
            .getSingle();
        expect(n.read<int>('n'), 0, reason: t);
      }
      final suggestions = AiMerchantSuggestionsDao(db);
      expect(
        await suggestions.putAnswer(
          merchantNorm: 'zawya coffee',
          categoryId: 'sys:dining',
          confidence: 88,
          source: AiSuggestionSourceCode.llm,
          at: _t1,
        ),
        1,
      );
      expect(
        (await suggestions.byMerchant('zawya coffee'))!.state,
        AiSuggestionStateCode.unconfirmed,
      );
      final queue = LlmCatQueueDao(db);
      await queue.enqueue('keyword cafe', at: _t1);
      expect(await queue.count(), 1);
      // The widened CHECKs.
      expect(
        await failureOf(
          db,
          "UPDATE transactions SET category_id = 'sys:dining', "
          "category_source = 'ai' WHERE id = 'e2'",
        ),
        isNull,
      );
      final outbox = OutboxDao(db);
      await outbox.enqueue(
        id: 'o-c',
        kind: OutboxKind.llmCatConfirmation,
        payload: {'merchantNorm': 'zawya coffee', 'verdict': 'right'},
        createdAt: _t1,
      );
      await outbox.enqueue(
        id: 'o-w',
        kind: OutboxKind.llmCatCorrection,
        payload: {'merchantNorm': 'zawya coffee', 'verdict': 'wrong'},
        createdAt: _t1,
      );
      expect(
        await failureOf(
          db,
          'INSERT INTO outbox (id, kind, payload, created_at) VALUES '
          "('o-x', 'llm_cat_other', '{}', $_t1)",
        ),
        DbWriteException.constraintCheck,
      );

      // The re-created view and triggers work: an old row is still found,
      // a new one is indexed, the offset limits still abort.
      Future<List<String>> search(String q) async => [
        for (final r
            in await db
                .customSelect(
                  'SELECT s.txn_id AS id FROM transactions_fts f '
                  'JOIN transactions_fts_src s ON s.id = f.rowid '
                  'WHERE transactions_fts MATCH ? ORDER BY 1',
                  variables: [Variable.withString(q)],
                )
                .get())
          r.read<String>('id'),
      ];
      expect(await search('zawya'), ['u6']);
      expect(
        await failureOf(
          db,
          'INSERT INTO transactions (id, account_id, source, direction, '
          'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
          'merchant_raw, category_source, created_at, updated_at) VALUES '
          "('new7', 'acc1', 'manual', 'expense', 4200, 'EGP', $_t1, 120, "
          "'Fresh Bakery', 'ai', $_t1, $_t1)",
        ),
        isNull,
      );
      expect(await search('bakery'), ['new7']);
      expect(
        await failureOf(
          db,
          'INSERT INTO offset_links (id, kind, expense_txn_id, '
          "source_txn_id, amount_minor, created_at) VALUES ('l7', 'refund', "
          "'new7', 'i1', 4201, $_t1)",
        ),
        DbWriteException.offsetExceedsExpense,
      );
      expect(
        await failureOf(
          db,
          "UPDATE transactions SET amount_minor = 1 WHERE id = 'e1'",
        ),
        DbWriteException.offsetExceedsExpense,
      );
    });
  }

  test('reopening a migrated v6 file is a plain open', () async {
    await prepareV6(world);
    await openedDb(await world.open(executor: foregroundExecutor)).close();
    final again = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(again.close);
    expect(again.attemptedUpgradeFrom, isNull);
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  for (final (what, extra) in [
    (
      'a stray "ai_merchant_suggestions" table',
      ['CREATE TABLE ai_merchant_suggestions (x TEXT)'],
    ),
    (
      'a stray "transactions__v7" table',
      ['CREATE TABLE transactions__v7 (x TEXT)'],
    ),
    (
      'a stray "outbox__v7" table, after transactions was rebuilt',
      ['CREATE TABLE outbox__v7 (x TEXT)'],
    ),
  ]) {
    test('a failing v6 → v7 step ($what) is DB_MIGRATION_FAILED(restored): '
        'every file byte-identical, still v6, rows intact', () async {
      await prepareV6(world, extra: extra);
      final rowsBefore = await snapshotV6(world);
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 6);
      expect(failed.toVersion, appSchemaVersion);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final after = await snapshotV6(world);
      expect(after.rows, rowsBefore.rows);
      final raw = V6Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 6);
    });
  }

  test('the opener never sees a v7 file as needing a migration', () async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(db.close);
    expect(await userVersionOf(db), appSchemaVersion);
    expect(db.attemptedUpgradeFrom, isNull);
  });
}
