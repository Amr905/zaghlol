// T-080: state behind S-12. Widgets read these providers only.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database_providers.dart';
import '../../../budget/application/budget_providers.dart'
    show transactionsChangedProvider;
import '../../data/transaction_detail_reader.dart';
import '../../data/transactions_providers.dart';

/// The detail of one transaction; refreshes when anything changes. A null
/// value means the transaction no longer exists.
final txnDetailProvider = FutureProvider.autoDispose.family<TxnDetail?, String>(
  (ref, id) async {
    final db = await ref.watch(appDatabaseProvider.future);
    final repo = await ref.watch(transactionRepositoryProvider.future);
    final sub = ref.watch(transactionsChangedProvider).listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return TransactionDetailReader(db, repo).read(id);
  },
  name: 'txnDetailProvider',
);
