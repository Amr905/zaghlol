// T-080: providers behind S-13.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database_providers.dart';
import '../../../../core/db/daos/accounts_dao.dart';
import '../../application/transaction_editor.dart';
import '../../data/transactions_providers.dart';
import '../list/txn_list_providers.dart';

final transactionEditorProvider = FutureProvider<TxnEditorPort>((ref) async {
  return TransactionEditor(
    await ref.watch(transactionRepositoryProvider.future),
    await ref.watch(transferPairingUseCaseProvider.future),
    await ref.watch(refundMatchingProvider.future),
  );
}, name: 'transactionEditorProvider');

/// The id of the default Cash account (FR-ACC-03), null when none exists.
final defaultCashAccountIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return (await AccountsDao(db).defaultCash())?.id;
}, name: 'defaultCashAccountIdProvider');
