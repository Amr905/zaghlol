// T-233: the ingest hook offers every stored transfer leg to pairing, so an
// own-account transfer that arrived by SMS is internal (not spend, not
// income). Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing_hook.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    final accounts = AccountsDao(db);
    await accounts.insert(account('cib', institution: 'CIB', last4: '7316'));
    await accounts.insert(account('nbe', institution: 'NBE', last4: '9921'));
  });
  tearDown(() => edb.close());

  TransferPairingHook hook() => TransferPairingHook(
    TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
    ),
  );

  Future<void> leg(String id, String acc, bool out, int at) =>
      TransactionsDao(db).insert(
        txn(
          id,
          accountId: acc,
          direction: out ? 'transfer_out' : 'transfer_in',
          amountMinor: 200000,
          occurredAt: t0 + at,
        ),
      );

  Future<Map<String, int>> internal() async => {
    for (final r
        in await db
            .customSelect('SELECT id, is_internal AS i FROM transactions')
            .get())
      r.read<String>('id'): r.read<int>('i'),
  };

  test('both legs of an own-account transfer become internal', () async {
    await leg('o', 'cib', true, 0);
    await hook().afterPersist(
      const PersistedTxn(txnId: 'o', accountId: 'cib', inserted: true),
    );
    await leg('i', 'nbe', false, 60000);
    await hook().afterPersist(
      const PersistedTxn(txnId: 'i', accountId: 'nbe', inserted: true),
    );
    expect(await internal(), {'o': 1, 'i': 1});
  });

  test('legs further apart than the window stay as they are', () async {
    await leg('o', 'cib', true, 0);
    await leg('i', 'nbe', false, 3600000);
    await hook().afterPersist(
      const PersistedTxn(txnId: 'i', accountId: 'nbe', inserted: true),
    );
    expect(await internal(), {'o': 0, 'i': 0});
  });

  test('a failing pairing never throws out of the hook', () async {
    await hook().afterPersist(
      const PersistedTxn(txnId: '', accountId: 'cib', inserted: true),
    );
  });
}
