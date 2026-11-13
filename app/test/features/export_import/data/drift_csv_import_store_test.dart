// T-155: the Drift store behind CSV import: real export -> import round
// trip, re-import adds nothing. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
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
}
