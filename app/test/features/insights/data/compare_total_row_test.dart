// FU-186a: the card compare table's Total cell (cardsSplit spend) must equal
// the sum of that card's cells (categoryDonut slices). Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail_providers.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

int at(int d, [int m = 11]) =>
    DateTime.utc(2026, m, d, 10).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  final period = ChartPeriod(CivilDate(2026, 11, 1), CivilDate(2026, 11, 30));
  final egp = Currency.of('EGP');

  Future<void> add(
    String id,
    String account,
    int amount,
    String? category, {
    int? when,
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: account,
          amountMinor: amount,
          occurredAt: when ?? at(3),
        ).copyWith(categoryId: Value(category)),
      );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('bank'));
    await db.into(db.accounts).insert(account('card2', last4: '2222'));
    await db
        .into(db.accounts)
        .insert(account('wallet', kind: 'cash', last4: null));
    for (final id in ['sys:groceries', 'sys:dining', 'sys:cash']) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              nameAr: id,
              nameEn: id,
              icon: 'x',
              color: '#000000',
              bucket: 'needs',
              sort: 0,
            ),
          );
    }
  });
  tearDown(() => edb.close());

  Future<void> expectTotalsMatch() async {
    final charts = ChartRepository(db);
    final split = await charts.cardsSplit(period, ChartFilter(currency: egp));
    expect(split, isA<ChartReady<List<CardSpend>>>());
    for (final c in (split as ChartReady<List<CardSpend>>).data) {
      final donut = await charts.categoryDonut(
        period,
        ChartFilter(currency: egp, accountIds: {c.accountId}),
      );
      final cells = donut is ChartReady<CategoryDonut>
          ? donut.data.slices.fold<int>(0, (a, s) => a + s.amount.minor)
          : 0;
      final data = donut is ChartReady<CategoryDonut> ? donut.data : null;
      expect(cells, c.spend.minor + (data?.coveredEarlier?.minor ?? 0));
      expect(
        compareCardTotal(c, data).minor,
        cells,
        reason: 'card ${c.accountId}',
      );
    }
  }

  test('plain spending: Total equals the sum of the cells', () async {
    await add('a', 'bank', 1000, 'sys:groceries');
    await add('b', 'bank', 250, 'sys:dining');
    await add('c', 'bank', 75, null);
    await add('d', 'card2', 400, 'sys:dining');
    await expectTotalsMatch();
  });

  test(
    'cash paid from an earlier withdrawal: Total equals the cells',
    () async {
      await add('w', 'bank', 5000, 'sys:cash', when: at(20, 10));
      await add('p1', 'wallet', 8000, 'sys:groceries');
      await add('x', 'bank', 300, 'sys:dining');
      await expectTotalsMatch();
    },
  );
}
