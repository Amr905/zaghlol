// FU-181a: a split save that fails part-way leaves the old split untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/daos/transfers_dao.dart';
import 'package:zaghlol/features/transactions/application/reimbursements.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol/features/transfers/data/drift_transfers_sheet_port.dart';
import 'package:zaghlol/features/transfers/presentation/transfers_port.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

class _Unused implements TransactionRepository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _UnusedPairing implements TransferPairingUseCase {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late Reimbursements uc;
  late DriftTransfersSheetPort port;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    await TransactionsDao(db).insert(txn('bill', amountMinor: 120000));
    var n = 0;
    uc = Reimbursements(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      newId: () => 'p${n++}',
    );
    port = DriftTransfersSheetPort(
      db: db,
      repo: _Unused(),
      reimbursements: uc,
      pairing: _UnusedPairing(),
      accountLabel: (_) => '',
      now: DateTime.now,
    );
  });
  tearDown(() => edb.close());

  test(
    'add that trips the share cap rolls back removals and updates',
    () async {
      final a = await uc.addParticipant('bill', 'A', 30000);
      final b = await uc.addParticipant('bill', 'B', 30000);
      await expectLater(
        port.saveSplit(
          'bill',
          [
            SplitEdit(id: a, name: 'A', shareMinor: 10000),
            const SplitEdit(name: 'C', shareMinor: 5000000),
          ],
          {b},
        ),
        throwsA(anything),
      );
      final rows = await SplitParticipantsDao(db).forExpense('bill');
      expect({for (final r in rows) r.id: r.shareMinor}, {a: 30000, b: 30000});
    },
  );
}
