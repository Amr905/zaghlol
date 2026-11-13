// T-093: providers behind S-15 / S-16. Widgets read these only.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../data/drift_transfers_sheet_port.dart';
import 'transfers_port.dart';

final transfersSheetPortProvider = FutureProvider<TransfersSheetPort>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final lookups = await ref.watch(txnLookupsProvider.future);
  final now = ref.watch(clockProvider);
  return DriftTransfersSheetPort(
    db: db,
    repo: await ref.watch(transactionRepositoryProvider.future),
    reimbursements: await ref.watch(reimbursementsProvider.future),
    pairing: await ref.watch(transferPairingUseCaseProvider.future),
    accountLabel: (id) => lookups.account(id)?.label ?? '',
    now: now,
  );
}, name: 'transfersSheetPortProvider');

/// S-15 Mode A data for one expense. Invalidate after a write.
final splitSheetDataProvider = FutureProvider.autoDispose
    .family<SplitData?, String>((ref, expenseId) async {
      final port = await ref.watch(transfersSheetPortProvider.future);
      return port.loadSplit(expenseId);
    }, name: 'splitSheetDataProvider');

/// S-15 Mode B data: the incoming transfer and its candidate expenses.
final assignSheetDataProvider = FutureProvider.autoDispose
    .family<AssignData?, ({String id, bool all})>((ref, key) async {
      final port = await ref.watch(transfersSheetPortProvider.future);
      return port.loadAssign(key.id, searchAll: key.all);
    }, name: 'assignSheetDataProvider');

/// S-16 data: the source leg and the matching candidates.
final linkSheetDataProvider = FutureProvider.autoDispose
    .family<LinkData?, String>((ref, id) async {
      final port = await ref.watch(transfersSheetPortProvider.future);
      return port.loadLink(id);
    }, name: 'linkSheetDataProvider');
