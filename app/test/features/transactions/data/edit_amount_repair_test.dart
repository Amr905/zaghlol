// T-080: an amount edit repairs offset links inside the edit's own
// transaction (EC-40). All data synthetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/reimbursements.dart';
import 'package:zaghlol/features/transactions/data/amount_repair_events.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late Reimbursements reimb;
  late DriftTransactionRepository repo;
  var n = 0;

  setUp(() async {
    n = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    final dao = TransactionsDao(db);
    await dao.insert(
      txn('bill', accountId: 'acc1', direction: 'expense', amountMinor: 120000),
    );
    await dao.insert(
      txn(
        'back',
        accountId: 'acc1',
        direction: 'transfer_in',
        amountMinor: 40000,
      ),
    );
    reimb = Reimbursements(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      newId: () => 'p${n++}',
    );
    await reimb.assign('back', [
      const AssignRequest(expenseId: 'bill', amountMinor: 40000),
    ]);
    repo = DriftTransactionRepository(
      dao,
      onAmountChange: (id, minor) async =>
          (await reimb.repairForNewAmount(id, minor)).removedLinkIds,
    );
  });

  tearDown(() => edb.close());

  test('shrinking below the linked money removes the link and saves', () async {
    final out = await repo.editWithOutcome(
      'bill',
      TransactionEdit(amount: Money(Currency.of('EGP'), 30000)),
    );
    expect(out.removedLinkIds, hasLength(1));
    expect(out.record.amount.minor, 30000);
    expect(await OffsetLinksDao(db).forExpense('bill'), isEmpty);
  });

  test('an amount that still fits keeps the links', () async {
    final out = await repo.editWithOutcome(
      'bill',
      TransactionEdit(amount: Money(Currency.of('EGP'), 90000)),
    );
    expect(out.removedLinkIds, isEmpty);
    expect(await OffsetLinksDao(db).forExpense('bill'), hasLength(1));
  });

  test('a note-only edit does not touch links', () async {
    final out = await repo.editWithOutcome(
      'bill',
      const TransactionEdit(note: Maybe('x')),
    );
    expect(out.removedLinkIds, isEmpty);
    expect(await OffsetLinksDao(db).forExpense('bill'), hasLength(1));
  });

  test(
    'FU-158a: the repair event is held, then published after commit',
    () async {
      final repairs = AmountRepairEvents(reimb);
      final edited = DriftTransactionRepository(
        TransactionsDao(db),
        onAmountChange: repairs.onAmountChange,
      );
      final bus = DomainEventBus();
      final seen = <DomainEvent>[];
      bus.events.listen(seen.add);
      addTearDown(bus.dispose);

      await edited.editWithOutcome(
        'bill',
        TransactionEdit(amount: Money(Currency.of('EGP'), 30000)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty, reason: 'nothing before the commit hook');

      repairs.flush(bus);
      await Future<void>.delayed(Duration.zero);
      expect(seen.single, isA<TransactionsChanged>());
      expect((seen.single as TransactionsChanged).accountIds, contains('acc1'));

      repairs.flush(bus);
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1), reason: 'released once');
    },
  );

  test('FU-274: a rolled-back edit discards its held repair event', () async {
    final repairs = AmountRepairEvents(reimb);
    final edited = DriftTransactionRepository(
      TransactionsDao(db),
      onAmountChange: (id, minor) async {
        await repairs.onAmountChange(id, minor);
        throw StateError('boom');
      },
      onRollback: repairs.discard,
    );
    final bus = DomainEventBus();
    final seen = <DomainEvent>[];
    bus.events.listen(seen.add);
    addTearDown(bus.dispose);
    await expectLater(
      edited.editWithOutcome(
        'bill',
        TransactionEdit(amount: Money(Currency.of('EGP'), 30000)),
      ),
      throwsStateError,
    );
    repairs.flush(bus);
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
  });
}
