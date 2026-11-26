// T-287 (FU-380): the per-currency feed decides "this month" from each row's
// stored offset, not the device zone. Synthetic data only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/home/application/currency_view_providers.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';

import '../presentation/currency_view_harness.dart';

TransactionRecord row(String id, DateTime utc, int offsetMin) =>
    TransactionRecord(
      id: id,
      accountId: 'a1',
      source: TxnSource.manual,
      direction: TxnDirection.income,
      status: TxnStatus.posted,
      amount: usdMoney(100),
      occurredAt: utc,
      occurredTzOffsetMin: offsetMin,
      categorySource: CategorySource.none,
      isUserVerified: false,
      isInternal: false,
      createdAt: utc,
      updatedAt: utc,
    );

void main() {
  test(
    'stored offset decides the cycle day, whatever the device zone',
    () async {
      final rows = [
        // 23:30 -05:00 on the last cycle day = Dec 1 04:30 UTC.
        row('last', DateTime.utc(2026, 12, 1, 4, 30), -300),
        // 00:30 +03:00 on the first cycle day = Oct 31 21:30 UTC.
        row('first', DateTime.utc(2026, 10, 31, 21, 30), 180),
        // Dec 1 00:30 +03:00 = Nov 30 21:30 UTC: next cycle by its own offset.
        row('after', DateTime.utc(2026, 11, 30, 21, 30), 180),
        // Oct 31 23:30 -05:00 = Nov 1 04:30 UTC: previous cycle by its offset.
        row('before', DateTime.utc(2026, 11, 1, 4, 30), -300),
      ];
      final c = ProviderContainer(
        overrides: [
          homeModelProvider.overrideWith((ref) async => storyModel()),
          primaryCurrencyProvider.overrideWith((ref) => Stream.value(egp)),
          budgetOffersHandledProvider.overrideWith((ref) => Stream.value({})),
          transactionRepositoryProvider.overrideWith(
            (ref) async => FakeTxns(rows),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(currencyViewProvider('USD'), (_, _) {});
      final m = await c.read(currencyViewProvider('USD').future);
      expect(m.feed.map((f) => f.record.id).toSet(), {'last', 'first'});
    },
  );
}
