// T-045: Riverpod wiring (ADR-001). The repository is built from the open
// database; the clock and id generator are the transactions feature's
// providers, so one override serves both in tests.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../transactions/data/transactions_providers.dart';
import '../domain/accounts_repository.dart';
import 'drift_accounts_repository.dart';

final accountsRepositoryProvider = FutureProvider<AccountsRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftAccountsRepository(
    AccountsDao(db),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  );
}, name: 'accountsRepositoryProvider');
