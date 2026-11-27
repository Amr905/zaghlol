// FREEZE-FIX: a v6 file that already holds rows pointing nowhere (data an
// older build left behind: a deleted category, a purged raw message, a gone
// transfer pair or account) still upgrades to v7 with every row kept as it
// was; the opener's FK check fails only on violations the steps add. Before
// the fix any such row made the upgrade fail (and be restored) on every
// launch. Data synthetic.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';

import '../../support/fake_secret_store.dart';
import 'db_open_harness.dart';
import 'fake_next_database.dart';
import 'migration_harness_test.dart' show settle;
import 'migration_v7_test.dart' show exactRows, prepareV6, snapshotV6;

const int _t = 1793527200000;
const String _cols =
    'INSERT INTO transactions (id, account_id, source, direction, '
    'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
    'merchant_raw, merchant_norm, category_id, category_source, '
    'is_user_verified, created_at, updated_at';

/// Dangling references of each kind on `transactions`, written with foreign
/// keys off (the v6 helper's create runs before they are turned on).
const List<String> _dirty = [
  "$_cols) VALUES ('dc', 'acc1', 'sms', 'expense', 100, 'EGP', $_t, 120, "
      "NULL, NULL, 'gone:category', 'user', 1, $_t, $_t)",
  "$_cols, raw_message_id) VALUES ('dr', 'acc1', 'sms', 'expense', 200, "
      "'EGP', $_t, 120, NULL, NULL, NULL, 'none', 0, $_t, $_t, 'gone:raw')",
  "$_cols, transfer_pair_id) VALUES ('dp', 'acc1', 'sms', 'transfer_out', "
      "300, 'EGP', $_t, 120, NULL, NULL, NULL, 'none', 0, $_t, $_t, "
      "'gone:pair')",
  "$_cols) VALUES ('da', 'gone:account', 'manual', 'expense', 400, 'EGP', "
      "$_t, 120, NULL, NULL, NULL, 'none', 0, $_t, $_t)",
];

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 'freeze_fk');
  });

  tearDown(() => world.dispose());

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';
    test('a v6 file with pre-existing dangling references upgrades to v7, '
        'every row kept byte for byte, the dangling ids too ($mode)', () async {
      await prepareV6(world, extra: _dirty);
      final before = await snapshotV6(world);

      final result = await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      );
      expect(result, isA<DbOpened<AppDatabase>>(), reason: '$result');
      final db = (result as DbOpened<AppDatabase>).db;
      addTearDown(db.close);
      expect(result.migratedFrom, 6);
      expect(await userVersionOf(db), 7);
      expect(world.files.migrateTmp.existsSync(), isFalse);

      final rows = await db
          .customSelect(
            'SELECT id, account_id, category_id, raw_message_id, '
            "transfer_pair_id FROM transactions WHERE id IN ('dc', 'dr', "
            "'dp', 'da') ORDER BY id",
          )
          .get();
      expect(
        [for (final r in rows) r.data],
        [
          {
            'id': 'da',
            'account_id': 'gone:account',
            'category_id': null,
            'raw_message_id': null,
            'transfer_pair_id': null,
          },
          {
            'id': 'dc',
            'account_id': 'acc1',
            'category_id': 'gone:category',
            'raw_message_id': null,
            'transfer_pair_id': null,
          },
          {
            'id': 'dp',
            'account_id': 'acc1',
            'category_id': null,
            'raw_message_id': null,
            'transfer_pair_id': 'gone:pair',
          },
          {
            'id': 'dr',
            'account_id': 'acc1',
            'category_id': null,
            'raw_message_id': 'gone:raw',
            'transfer_pair_id': null,
          },
        ],
      );
      // The same four violations as before the upgrade, no more.
      expect(
        await db.customSelect('PRAGMA foreign_key_check').get(),
        hasLength(4),
      );
      for (final t in ['transactions', 'outbox']) {
        expect(
          await exactRows(db, t, before.columns[t]!),
          before.rows[t],
          reason: t,
        );
      }
    });
  }

  test('a step that adds a violation still fails and is restored, with the '
      'cause named, on a file that already had dangling rows', () async {
    // A current-version file with a pre-existing dangling row.
    await prepareV6(world, extra: _dirty);
    final db7 = openedDb<AppDatabase>(
      await world.open(executor: foregroundExecutor),
    );
    await db7.close();
    await settle(world);

    final result = await world.openWith(
      fakeNextFactory(mode: FakeNextMode.fkViolation),
      FakeNextDatabase.version,
      executor: foregroundExecutor,
    );
    expect(result, isA<DbOpenFailed<FakeNextDatabase>>());
    final failed = result as DbOpenFailed;
    expect(failed.code, DbOpenFailureCode.migrationFailed);
    expect(failed.restored, isTrue);
    expect(failed.cause, 'DB_MIGRATION_FK_VIOLATION');
  });

  test('a step that clears an old violation and adds a new one in the same '
      'tables (equal counts) still fails and is restored', () async {
    await prepareV6(world, extra: _dirty);
    final db7 = openedDb<AppDatabase>(
      await world.open(executor: foregroundExecutor),
    );
    await db7.close();
    await settle(world);

    final result = await world.openWith(
      fakeNextFactory(mode: FakeNextMode.fkSwap),
      FakeNextDatabase.version,
      executor: foregroundExecutor,
    );
    expect(result, isA<DbOpenFailed<FakeNextDatabase>>());
    final failed = result as DbOpenFailed;
    expect(failed.restored, isTrue);
    expect(failed.cause, 'DB_MIGRATION_FK_VIOLATION');

    final db = openedDb<AppDatabase>(
      await world.open(executor: foregroundExecutor),
    );
    addTearDown(db.close);
    final rows = await db
        .customSelect(
          "SELECT id, category_id FROM transactions WHERE id IN ('dc', 'dr') "
          'ORDER BY id',
        )
        .get();
    expect(
      [for (final r in rows) r.data],
      [
        {'id': 'dc', 'category_id': 'gone:category'},
        {'id': 'dr', 'category_id': null},
      ],
    );
  });
}
