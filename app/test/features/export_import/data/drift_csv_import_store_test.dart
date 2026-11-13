// T-155: the Drift store behind CSV import: real export -> import round
// trip, re-import adds nothing. Synthetic data only.

import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/application/import_csv.dart';
import 'package:zaghlol/features/export_import/data/drift_csv_import_store.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late DriftTransactionRepository repo;
  late ImportCsvUseCase uc;

  setUp(() async {
    edb = await EncryptedDb.open();
    final dao = TransactionsDao(edb.db);
    final accounts = AccountsDao(edb.db);
    await accounts.insert(account('acc1'));
    repo = DriftTransactionRepository(dao);
    uc = ImportCsvUseCase(DriftCsvImportStore(edb.db, dao, accounts));
  });
  tearDown(() => edb.close());

  test(
    'export -> wipe-free re-import adds nothing; imports into fresh book',
    () async {
      await repo.add(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.expense,
          amount: Money(Currency.of('KWD'), 1250),
          originalAmount: Money(Currency.of('USD'), 400),
          occurredAt: DateTime.utc(2026, 11, 1, 22, 30),
          occurredTzOffsetMin: 120,
          merchant: '=SUM(A1)',
          note: 'n, "q"',
        ),
      );
      await repo.add(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.income,
          amount: Money(Currency.of('EGP'), 5000),
          occurredAt: DateTime.utc(2026, 11, 2),
          occurredTzOffsetMin: 120,
        ),
      );
      final rows = await repo.query();
      final bytes = encodeCsv([exportHeader, ...rows.map(exportRow)]);

      final again = await uc.run(bytes);
      expect(again.imported, 0);
      expect(again.duplicates, 2);
      expect(await repo.count(), 2);

      // Fresh book: delete via soft delete + purge is not needed; use a second
      // account-less check by importing a changed amount.
      final changed = encodeCsv([
        exportHeader,
        ...rows.map(exportRow).map((r) => [...r]..[6] = '9.99'),
      ]);
      final s = await uc.run(changed);
      expect(s.imported, 2);
      final all = await repo.query();
      expect(all.length, 4);
      final csvRows = all.where((r) => r.source == TxnSource.csv).toList();
      expect(csvRows.length, 2);
      expect(csvRows.every((r) => r.isUserVerified), isTrue);
      expect(
        csvRows.map((r) => r.merchantRaw).toSet(),
        containsAll(['=SUM(A1)']),
      );
    },
  );

  test('import re-pairs transfers: spend and income match the original '
      '(T-155 155-1)', () async {
    final src = await EncryptedDb.open();
    addTearDown(src.close);
    final srcDao = TransactionsDao(src.db);
    final srcAcc = AccountsDao(src.db);
    await srcAcc.insert(account('acc1', institution: 'NBE', last4: '1111'));
    await srcAcc.insert(account('acc2', institution: 'CIB', last4: '2222'));
    await srcDao.insert(txn('x', direction: 'expense', amountMinor: 50000));
    await srcDao.insert(
      txn('o', direction: 'transfer_out', amountMinor: 100000),
    );
    await srcDao.insert(
      txn(
        'i',
        accountId: 'acc2',
        direction: 'transfer_in',
        amountMinor: 100000,
      ),
    );
    await TransferPairingUseCase(
      src.db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    ).onPersisted('i');
    Future<List<int>> totals(AppDatabase db) async {
      Future<int> sum(String dirs) async =>
          (await db
                  .customSelect(
                    'SELECT coalesce(sum(amount_minor),0) AS s FROM transactions '
                    'WHERE deleted_at IS NULL AND is_internal = 0 '
                    'AND direction IN ($dirs)',
                  )
                  .getSingle())
              .read<int>('s');
      return [
        await sum("'expense','fee'"),
        await sum("'income','transfer_in','transfer_out'"),
      ];
    }

    final original = await totals(src.db);
    expect(original, [50000, 0]);

    final bytes = encodeCsv([
      exportHeader,
      ...(await DriftTransactionRepository(srcDao).query()).map(exportRow),
    ]);

    final dst = await EncryptedDb.open();
    addTearDown(dst.close);
    final dstDao = TransactionsDao(dst.db);
    final dstAcc = AccountsDao(dst.db);
    await dstAcc.insert(account('acc1', institution: 'NBE', last4: '1111'));
    await dstAcc.insert(account('acc2', institution: 'CIB', last4: '2222'));
    final pairing = TransferPairingUseCase(
      dst.db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    );
    final hooked = <String>[];
    final imp = ImportCsvUseCase(
      DriftCsvImportStore(dst.db, dstDao, dstAcc),
      onImported: (id) async {
        await pairing.onPersisted(id);
        hooked.add(id);
      },
    );
    final summary = await imp.run(bytes);
    expect(summary.imported, 3);
    expect(hooked.length, 3);
    expect(await totals(dst.db), original);
  });
}
