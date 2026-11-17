// FU-253 (FU-142): the repository's delete (the voice logger's Undo goes
// through it) frees pairs and offset links like the bulk and ignore-rule
// deletes. Fails without the `afterRemove` wiring: the surviving leg stayed
// internal and its amount never counted again.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  test('softDelete through the provider dissolves the pair and frees the '
      'surviving leg', () async {
    final edb = await EncryptedDb.open();
    addTearDown(edb.close);
    final db = edb.db;
    await AccountsDao(db)
        .insert(account('nbe', institution: 'NBE', last4: '1111'));
    await AccountsDao(db)
        .insert(account('cib', institution: 'CIB', last4: '2222'));
    for (final (id, acc, dir, at) in [
      ('o', 'nbe', 'transfer_out', 0),
      ('i', 'cib', 'transfer_in', 60000),
    ]) {
      await TransactionsDao(db).insert(
        txn(
          id,
          accountId: acc,
          direction: dir,
          amountMinor: 50000,
          occurredAt: t0 + at,
        ).copyWith(status: const Value('posted')),
      );
    }
    final pairing = TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(t0 + 3600000, isUtc: true),
      newId: () => 'p1',
    );
    await pairing.onPersisted('i');
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => edb.db),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(t0 + 7200000, isUtc: true),
        ),
      ],
    );
    addTearDown(c.dispose);
    final repo = await c.read(transactionRepositoryProvider.future);
    await repo.softDelete(['o']);
    expect(
      await db.customSelect('SELECT id FROM transfer_pairs').get(),
      isEmpty,
    );
    final i = await db
        .customSelect(
          "SELECT is_internal AS x FROM transactions WHERE id = 'i'",
        )
        .getSingle();
    expect(i.read<int>('x'), 0);
  });
}
