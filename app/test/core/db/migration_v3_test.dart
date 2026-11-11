// T-018: the real v2 → v3 step (design note §1, §6, §7; database-schema §4)
// on an encrypted file through the app's opener: the pre-migration copy is
// made and deleted, the v2 rows survive (search still finds them), the
// migrated schema equals a fresh v3 and the committed v3 dump, the FK check
// is clean, the new tables work (trigram candidates), FTS5 secure-delete is
// on, and the T-017 review fixes m-1 / m-2 are live. A failing step is
// rolled back byte for byte. Also: the frozen step equals the dumps. Keys
// and data synthetic.

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/fts_options.dart';
import 'package:zaghlol/core/db/migrations/v3_financial_b.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import '../../support/file_snapshot.dart';
import 'app_database_test.dart' show dumpFile;
import 'db_open_harness.dart';
import 'fake_next_database.dart';
import 'financial_fixtures.dart' show failureOf, link;
import 'fts_probe.dart' show secureDeleteOf;
import 'migration_harness_test.dart' show settle;
import 'migration_v2_test.dart' show dumpShape, freshShape;
import 'schema_v2_database.dart';

/// (entity name, sqlite statement) of dump [version], in dump order.
List<(String, String)> dumpEntries(int version) {
  final json =
      jsonDecode(dumpFile(version).readAsStringSync()) as Map<String, Object?>;
  return [
    for (final e
        in (json['fixed_sql']! as List<Object?>).cast<Map<String, Object?>>())
      for (final s in (e['sql']! as List<Object?>).cast<Map<String, Object?>>())
        if (s['dialect'] == 'sqlite')
          (e['name']! as String, s['sql']! as String),
  ];
}

/// Puts the bootstrap key (seed 61) in the store, then replaces the
/// database with a v2 file.
Future<void> prepareV2(DbWorld world, {List<String> extra = const []}) async {
  final first = openedDb(await world.open(executor: foregroundExecutor));
  await first.close();
  for (final f in world.dbDir.listSync()) {
    f.deleteSync();
  }
  await makeV2File(world.mainFile, extra: extra);
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 't018_mig');
  });

  tearDown(() => world.dispose());

  test('the frozen v2 → v3 statements are the v3 dump entries that are new '
      'or changed since v2, in order, without IF NOT EXISTS', () {
    final v2 = {for (final (n, s) in dumpEntries(2)) n: s};
    final v3 = dumpEntries(3);
    expect(v3.map((e) => e.$1).toSet().containsAll(v2.keys), isTrue);
    final expected = [
      for (final (name, sql) in v3)
        if (v2[name] != sql)
          (
            name,
            sql
                .replaceFirst('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE')
                .replaceFirst(
                  'CREATE VIRTUAL TABLE IF NOT EXISTS',
                  'CREATE VIRTUAL TABLE',
                ),
          ),
    ];
    expect(v3AddedObjects, expected);
    expect(
      v3AddedObjects.every((o) => !o.$2.contains('IF NOT EXISTS')),
      isTrue,
    );
    // The dropped triggers are exactly the v2 objects whose SQL changed.
    final changed = [
      for (final (name, sql) in v3)
        if (v2.containsKey(name) && v2[name] != sql) name,
    ];
    expect(v3DroppedTriggers, changed);
    expect(changed, ['trg_offset_links_bi', 'trg_offset_links_bu']);
  });

  test('the v3 FTS options are the current ones (change both in a new '
      'version, never the frozen copy)', () {
    expect(v3FtsOptions, ftsOptionStatements);
  });

  test('the v2 helper equals the committed v2 dump', () async {
    final db = V2Database(NativeDatabase.memory(), populated: false);
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(
      sameSchemaShape(await schemaShapeOf(db), await dumpShape(2)),
      isTrue,
    );
  });

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';

    test('v2 → v3 through the opener: copy made then deleted, rows kept, '
        'schema = fresh v3 = dump, FK check clean, new tables, secure-delete, '
        'm-1/m-2 live ($mode)', () async {
      await prepareV2(world);
      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      final opened = result as DbOpened<AppDatabase>;
      final db = opened.db;
      addTearDown(db.close);
      expect(opened.migratedFrom, 2);
      expect(db.attemptedUpgradeFrom, 2);
      expect(await userVersionOf(db), 3);
      expect(world.files.migrateTmp.existsSync(), isFalse);
      expect(world.files.migratePart.existsSync(), isFalse);
      expect(await metaValue(db, 'marker'), 'v2');

      final live = await schemaShapeOf(db);
      expect(sameSchemaShape(live, await freshShape()), isTrue);
      expect(sameSchemaShape(live, await dumpShape(3)), isTrue);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      // v2 rows and their search index survive.
      final txns = TransactionsDao(db);
      expect([for (final r in await txns.search('العزب')) r.id], ['e1']);
      expect([for (final r in await txns.search('١٢٥٠٫٥٠')) r.id], ['e1']);
      expect(
        (await db
                .customSelect(
                  "SELECT amount_minor FROM offset_links WHERE id = 'l1'",
                )
                .getSingle())
            .read<int>('amount_minor'),
        25000,
      );

      // S-2: secure-delete on the migrated file.
      expect(await secureDeleteOf(db, 'transactions_fts'), 1);
      expect(await secureDeleteOf(db, 'transactions_fts_short'), 1);

      // m-1: a missing expense fails the FK.
      await expectLater(
        OffsetLinksDao(db)
            .insert(link('l2', expense: 'nope', source: 'i1', amountMinor: 1)),
        throwsA(
          isA<DbWriteException>().having(
            (e) => e.code,
            'code',
            DbWriteException.constraintForeignKey,
          ),
        ),
      );
      // The offset sums still hold (re-created triggers).
      await expectLater(
        OffsetLinksDao(
          db,
        ).insert(link('l3', expense: 'e2', source: 'i1', amountMinor: 25001)),
        throwsA(
          isA<DbWriteException>().having(
            (e) => e.code,
            'code',
            DbWriteException.offsetExceedsSource,
          ),
        ),
      );
      // m-2: the linked participant can't move.
      expect(
        await failureOf(
          db,
          "UPDATE split_participants SET expense_txn_id = 'e2' "
          "WHERE id = 'p1'",
        ),
        DbWriteException.offsetParticipantMismatch,
      );

      // New tables work.
      final catalog = CatalogDao(db);
      await catalog.upsertMerchant(
        CatalogMerchantsCompanion.insert(
          canonical: 'El Ezaby',
          categoryCode: 'health',
          version: 1,
        ),
      );
      final id =
          (await db
                  .customSelect('SELECT max(id) AS id FROM catalog_merchants')
                  .getSingle())
              .read<int>('id');
      await catalog.upsertAlias(
        merchantId: id,
        aliasNorm: 'ezaby',
        match: 'exact',
      );
      expect(
        [for (final a in await catalog.aliasCandidates('ezabi')) a.aliasNorm],
        ['ezaby'],
      );
      expect(
        await failureOf(
          db,
          'INSERT INTO budgets (id, currency, limit_minor, period, '
          "created_at) VALUES ('b1', 'EGP', 1.5, 'cycle', 0)",
        ),
        DbWriteException.constraintCheck,
      );
    });
  }

  test('reopening a migrated v2 file is a plain open (no copy, no upgrade; '
      'v1 → latest is in migration_v2_test.dart)', () async {
    final first = openedDb(await world.open(executor: foregroundExecutor));
    await first.close();
    for (final f in world.dbDir.listSync()) {
      f.deleteSync();
    }
    await makeV2File(world.mainFile, populated: false);
    await openedDb(await world.open(executor: foregroundExecutor)).close();
    final again = openedDb(await world.open(executor: foregroundExecutor));
    addTearDown(again.close);
    expect(again.attemptedUpgradeFrom, isNull);
    expect(world.files.migrateTmp.existsSync(), isFalse);
  });

  for (final (what, extra) in [
    (
      'a stray v2 "budgets" table',
      ['CREATE TABLE budgets (id TEXT PRIMARY KEY, junk INTEGER)'],
    ),
    (
      'a v2 file missing a trigger the step drops',
      ['DROP TRIGGER trg_offset_links_bu'],
    ),
  ]) {
    test('a failing v2 → v3 step ($what) is DB_MIGRATION_FAILED(restored): '
        'every file byte-identical, still v2', () async {
      await prepareV2(world, extra: extra);
      final before = snapshotFiles(world.dbDir);
      final result = await world.open();
      final failed = result as DbOpenFailed;
      expect(failed.code, DbOpenFailureCode.migrationFailed);
      expect(failed.restored, isTrue);
      expect(failed.fromVersion, 2);
      expect(failed.toVersion, 3);
      await settle(world);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect(world.wipeLog, isEmpty);

      final raw = V2Database(
        openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      );
      addTearDown(raw.close);
      expect(await userVersionOf(raw), 2);
      expect(await metaValue(raw, 'marker'), 'v2');
      expect(
        await raw
            .customSelect(
              "SELECT name FROM sqlite_schema WHERE name = 'catalog_aliases'",
            )
            .get(),
        isEmpty,
      );
    });
  }

  test(
    'v2 → next (FakeNextDatabase) runs the real v2 → v3 step first',
    () async {
      await prepareV2(world);
      final result = await world.openWith(
        fakeNextFactory(),
        FakeNextDatabase.version,
      );
      final opened = result as DbOpened<FakeNextDatabase>;
      addTearDown(opened.db.close);
      expect(opened.migratedFrom, 2);
      expect(await userVersionOf(opened.db), FakeNextDatabase.version);
      expect(
        sameSchemaShape(await schemaShapeOf(opened.db), await freshShape()),
        isTrue,
      );
      expect(await secureDeleteOf(opened.db, 'transactions_fts'), 1);
    },
  );
}
