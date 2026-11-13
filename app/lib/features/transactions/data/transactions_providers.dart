// T-050: Riverpod wiring (ADR-001). The repository is built from the open
// database; the clock and the id generator are providers so tests override
// them.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../application/reimbursements.dart';
import '../domain/transaction_repository.dart';
import 'drift_transaction_repository.dart';

final clockProvider = Provider<Clock>(
  (ref) => DateTime.now,
  name: 'transactionsClockProvider',
);

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => newUuidV4,
  name: 'transactionsIdGeneratorProvider',
);

final reimbursementsProvider = FutureProvider<Reimbursements>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return Reimbursements(
    db,
    loadSchedule: () => ref.read(paydayScheduleProvider.future),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    events: ref.watch(domainEventBusProvider),
  );
}, name: 'reimbursementsProvider');

final transactionRepositoryProvider = FutureProvider<TransactionRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final reimb = await ref.watch(reimbursementsProvider.future);
  return DriftTransactionRepository(
    TransactionsDao(db),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    // EC-40: runs inside the edit's own transaction, before the write.
    onAmountChange: (id, minor) async =>
        (await reimb.repairForNewAmount(id, minor)).removedLinkIds,
  );
}, name: 'transactionRepositoryProvider');
