// FU-142: the ingest hook offers every stored row to refund matching.
// Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/refund_matching_hook.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
  });
  tearDown(() => edb.close());

  RefundMatchingHook hook() => RefundMatchingHook(
    RefundMatching(db, loadSchedule: () async => PaydaySchedule.single(1)),
  );

  test('a stored refund is linked to its expense', () async {
    final dao = TransactionsDao(db);
    await dao.insert(
      txn(
        'e',
        accountId: 'acc1',
        direction: 'expense',
        amountMinor: 10000,
        merchantNorm: 'acme',
        occurredAt: t0 - 86400000,
      ),
    );
    await dao.insert(
      txn(
        'r',
        accountId: 'acc1',
        direction: 'refund',
        amountMinor: 3000,
        merchantNorm: 'acme',
        occurredAt: t0,
      ),
    );
    await hook().afterPersist(
      const PersistedTxn(txnId: 'r', accountId: 'acc1', inserted: true),
    );
    expect(await OffsetLinksDao(db).linkedToExpense('e'), 3000);
  });

  test('a failing match never throws out of the hook', () async {
    await hook().afterPersist(
      const PersistedTxn(txnId: '', accountId: 'acc1', inserted: true),
    );
  });
}
