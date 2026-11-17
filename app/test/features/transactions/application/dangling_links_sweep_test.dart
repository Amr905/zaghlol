// FU-253 (FU-142): a pair / offset link left pointing at a soft-deleted leg
// (crash between the delete and its hook) is freed at start. Fails without
// the sweep: the surviving leg stays internal and its spend never counts.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/dangling_links_sweep.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late TransferPairingUseCase pairing;
  late RefundMatching refunds;

  Future<void> add(String id, String account, String dir, int at) =>
      TransactionsDao(db).insert(
        txn(
          id,
          accountId: account,
          direction: dir,
          amountMinor: 50000,
          occurredAt: t0 + at,
        ).copyWith(status: const Value('posted')),
      );

  Future<int> sweep() => sweepDanglingLinks(
    db,
    onPairRemoved: (id) async {
      await pairing.onRemoved(id);
    },
    onOffsetRemoved: (id) async {
      await refunds.onRemoved(id);
    },
  );

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).get()).length;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db)
        .insert(account('nbe', institution: 'NBE', last4: '1111'));
    await AccountsDao(db)
        .insert(account('cib', institution: 'CIB', last4: '2222'));
    Future<PaydaySchedule> schedule() async => PaydaySchedule.single(1);
    pairing = TransferPairingUseCase(
      db,
      loadSchedule: schedule,
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(t0 + 3600000, isUtc: true),
      newId: () => 'p1',
    );
    refunds = RefundMatching(db, loadSchedule: schedule);
  });
  tearDown(() => edb.close());

  test('a pair whose leg was soft-deleted is dissolved; survivor counts again; '
      'nothing is deleted', () async {
    await add('o', 'nbe', 'transfer_out', 0);
    await add('i', 'cib', 'transfer_in', 60000);
    await pairing.onPersisted('i');
    expect(await count('SELECT id FROM transfer_pairs'), 1);
    // Crash window: soft delete committed, the hook never ran.
    await TransactionsDao(db).softDelete('o', at: t0 + 120000);
    expect(await sweep(), 1);
    expect(await count('SELECT id FROM transfer_pairs'), 0);
    final i = await db
        .customSelect(
          'SELECT is_internal AS x, transfer_pair_id AS p FROM '
          'transactions WHERE id = \'i\'',
        )
        .getSingle();
    expect(i.read<int>('x'), 0);
    expect(i.read<String?>('p'), isNull);
    expect(await count('SELECT id FROM transactions'), 2); // none deleted
    expect(await sweep(), 0); // idempotent
  });

  test('an offset link to a soft-deleted expense is freed', () async {
    await add('e', 'nbe', 'expense', 0);
    await add('r', 'nbe', 'refund', 60000);
    await db.customStatement(
      'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
      "amount_minor, created_at) VALUES ('l', 'refund', 'e', 'r', 1000, $t0)",
    );
    await TransactionsDao(db).softDelete('e', at: t0 + 120000);
    expect(await sweep(), 1);
    expect(await count('SELECT id FROM offset_links'), 0);
    expect(await sweep(), 0);
  });

  test('live legs are left alone', () async {
    await add('o', 'nbe', 'transfer_out', 0);
    await add('i', 'cib', 'transfer_in', 60000);
    await pairing.onPersisted('i');
    expect(await sweep(), 0);
    expect(await count('SELECT id FROM transfer_pairs'), 1);
  });

  test('one failing leg does not stop the others', () async {
    await add('o', 'nbe', 'transfer_out', 0);
    await add('i', 'cib', 'transfer_in', 60000);
    await pairing.onPersisted('i');
    await TransactionsDao(db).softDelete('o', at: t0 + 120000);
    final n = await sweepDanglingLinks(
      db,
      onPairRemoved: (_) async => throw StateError('x'),
      onOffsetRemoved: (_) async {},
    );
    expect(n, 0);
    expect(await sweep(), 1); // found again next run
  });
}
