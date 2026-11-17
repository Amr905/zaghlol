// FU-141: the editor runs the "categorized" hook (merchant-contribution
// offer) only when the user gave the row a category. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transaction_editor.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late TransactionEditor editor;
  late List<String> hooked;
  var fail = false;
  var nextId = 0;
  DateTime clock() =>
      DateTime.fromMillisecondsSinceEpoch(t0 + 1000, isUtc: true);
  Future<PaydaySchedule> schedule() async => PaydaySchedule.single(1);

  setUp(() async {
    nextId = 0;
    fail = false;
    hooked = [];
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1', institution: 'nbe'));
    await CategoriesDao(db).upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    editor = TransactionEditor(
      DriftTransactionRepository(
        TransactionsDao(db),
        clock: clock,
        newId: () => 'g${nextId++}',
      ),
      TransferPairingUseCase(
        db,
        loadSchedule: schedule,
        clock: clock,
        newId: () => 'p${nextId++}',
      ),
      RefundMatching(
        db,
        loadSchedule: schedule,
        clock: clock,
        newId: () => 'r${nextId++}',
      ),
      onCategorized: (id) async {
        hooked.add(id);
        if (fail) throw StateError('queue full');
      },
    );
  });
  tearDown(() => edb.close());

  NewTransaction leg({String? categoryId}) => NewTransaction(
    accountId: 'acc1',
    direction: TxnDirection.expense,
    amount: Money(Currency.of('EGP'), 4500),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    occurredTzOffsetMin: 120,
    categoryId: categoryId,
    merchant: 'Corner Shop',
  );

  test('add: hook only when a category was chosen', () async {
    final a = await editor.add([leg(categoryId: 'sys:food')]);
    await editor.add([leg()]);
    expect(hooked, [a.single]);
  });

  test('update: hook on a category set, not on other edits or a clear; '
      'a failing hook never fails the save', () async {
    final id = (await editor.add([leg()])).single;
    await editor.update(id, const TransactionEdit(note: Maybe('lunch')));
    await editor.update(id, const TransactionEdit(categoryId: Maybe(null)));
    expect(hooked, isEmpty);
    fail = true;
    final out = await editor.update(
      id,
      const TransactionEdit(categoryId: Maybe('sys:food')),
    );
    expect(hooked, [id]);
    expect(out.record.categoryId, 'sys:food');
  });
}
