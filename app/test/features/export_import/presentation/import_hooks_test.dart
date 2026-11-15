// T-158 fix: the import runner's post-persist hooks pair transfers.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/application/import_csv.dart';
import 'package:zaghlol/features/export_import/data/drift_csv_import_store.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb src;
  late EncryptedDb dst;

  setUp(() async {
    src = await EncryptedDb.open();
    dst = await EncryptedDb.open();
    for (final e in [src, dst]) {
      final a = AccountsDao(e.db);
      await a.insert(account('acc1'));
      await a.insert(account('acc2', last4: '5678'));
    }
  });
  tearDown(() async {
    await src.close();
    await dst.close();
  });

  Future<Uint8List> sourceCsv() async {
    final repo = DriftTransactionRepository(TransactionsDao(src.db));
    final at = DateTime.utc(2026, 11, 3, 10);
    await repo.add(
      NewTransaction(
        accountId: 'acc1',
        direction: TxnDirection.transferOut,
        amount: Money(Currency.of('EGP'), 100000),
        occurredAt: at,
        occurredTzOffsetMin: 120,
      ),
    );
    await repo.add(
      NewTransaction(
        accountId: 'acc2',
        direction: TxnDirection.transferIn,
        amount: Money(Currency.of('EGP'), 100000),
        occurredAt: at.add(const Duration(minutes: 1)),
        occurredTzOffsetMin: 120,
      ),
    );
    final rows = await repo.query();
    return encodeCsv([exportHeader, ...rows.map(exportRow)]);
  }

  ImportCsvUseCase useCase() {
    final db = dst.db;
    final pairing = TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule([PaydayEra(null, 1)]),
    );
    final refunds = RefundMatching(
      db,
      loadSchedule: () async => PaydaySchedule([PaydayEra(null, 1)]),
    );
    return ImportCsvUseCase(
      DriftCsvImportStore(db, TransactionsDao(db), AccountsDao(db)),
      onImported: importPostPersistHook(pairing, refunds),
    );
  }

  Future<int> linked() async {
    final rows = await dst.db
        .customSelect('SELECT COUNT(*) c FROM transfer_pairs')
        .getSingle();
    return rows.read<int>('c');
  }

  test('both legs imported: pair linked, excluded from spending', () async {
    final bytes = await sourceCsv();
    final s = await useCase().run(bytes);
    expect(s.imported, 2);
    expect(await linked(), 1);
    final again = await useCase().run(bytes);
    expect(again.imported, 0);
    expect(await linked(), 1);
  });
}
