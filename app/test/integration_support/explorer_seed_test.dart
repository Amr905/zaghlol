// TEST-explorer: the explorer's synthetic data seeds an empty database and
// the app's own repositories read it back (EGP and USD stay separate).

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';

import '../../integration_test/support/explorer_seed.dart';

void main() {
  test(
    'seeds accounts, 30 transactions in two currencies, review items',
    () async {
      final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
      final c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      final r = await seedExplorerData(c, now: DateTime.utc(2026, 11, 16, 9));
      expect(r.accountIds, hasLength(5));
      expect(r.transactions, 30);
      expect(r.reviewItems, 2);
      final txns = await c.read(transactionRepositoryProvider.future);
      final rows = await txns.query();
      expect(rows.length, 30);
      expect(rows.map((t) => t.amount.currency.code).toSet(), {'EGP', 'USD'});
      final accounts = await c.read(accountsRepositoryProvider.future);
      expect((await accounts.list()).length, 5);
    },
  );
}
