// T-079: bulk delete goes through the removal hooks (FU-127 / FU-142).
// Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/bulk_actions.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late BulkActions actions;
  var nextId = 0;
  DateTime clock() =>
      DateTime.fromMillisecondsSinceEpoch(t0 + 1000, isUtc: true);
  Future<PaydaySchedule> schedule() async => PaydaySchedule.single(1);

  Future<void> add(String id, String account, {required bool out}) =>
      TransactionsDao(db).insert(
        txn(
          id,
          accountId: account,
          direction: out ? 'transfer_out' : 'transfer_in',
          amountMinor: 100000,
          currency: 'EGP',
          occurredAt: t0,
        ),
      );

  Future<int> pairCount() async =>
      (await db.customSelect('SELECT id FROM transfer_pairs').get()).length;

  setUp(() async {
    nextId = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db)
        .insert(account('nbe', institution: 'NBE', last4: '1111'));
    await AccountsDao(db)
        .insert(account('cib', institution: 'CIB', last4: '2222'));
    await CategoriesDao(db).upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    final pairing = TransferPairingUseCase(
      db,
      loadSchedule: schedule,
      clock: clock,
      newId: () => 'p${nextId++}',
    );
    actions = BulkActions(
      bulk: BulkEditUseCase(
        db,
        clock: clock,
        newId: () => 'b${nextId++}',
        loadSchedule: schedule,
      ),
      pairing: pairing,
      refunds: RefundMatching(
        db,
        loadSchedule: schedule,
        clock: clock,
        newId: () => 'r${nextId++}',
      ),
    );
    await add('o', 'nbe', out: true);
    await add('i', 'cib', out: false);
    await pairing.onPersisted('i');
  });

  tearDown(() => edb.close());

  test('bulk delete of a paired leg dissolves the pair and frees the other '
      'leg (FU-127)', () async {
    expect(await pairCount(), 1);
    final res = await actions.delete({'o'});
    expect(res.changed, 1);
    expect(await pairCount(), 0);
    final i = await TransactionsDao(db).byId('i');
    expect(i!.isInternal, 0);
    expect(i.deletedAt, isNull);
  });

  test(
    'bulk delete rolls nothing half-way: unknown id changes no row',
    () async {
      Object? error;
      try {
        await actions.delete({'o', 'missing'});
      } on BulkEditException catch (e) {
        error = e.code;
      }
      expect(error, BulkEditException.notFound);
      expect(await pairCount(), 1);
      expect((await TransactionsDao(db).byId('o'))!.deletedAt, isNull);
    },
  );

  test('Undo of a bulk category change restores rows', () async {
    final r = await actions.setCategory({'o', 'i'}, 'sys:food');
    expect(r.changed, 2);
    final u = await actions.undo(r.batchId);
    expect(u.restored, 2);
  });
}
