// T-169: Smart ROI providers: flag gate and signal mapping with a fake
// chart repository (synthetic figures).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/features/insights/data/chart_providers.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/roi/data/roi_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart'
    show clockProvider;
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

class FakeCharts implements ChartRepository {
  int calls = 0;
  ChartPeriod? lastPeriod;

  @override
  Future<ChartResult<CategoryDonut>> categoryDonut(
    ChartPeriod p,
    ChartFilter f,
  ) async {
    calls++;
    lastPeriod = p;
    // 3 months of groceries: 12,600 EGP over 18 rows (4,200/mo, 6 runs).
    return ChartReady(
      CategoryDonut(
        total: Money(f.currency, 1260000),
        slices: [
          CategorySlice(
            categoryId: 'groceries',
            amount: Money(f.currency, 1260000),
            shareBp: 10000,
            count: 18,
          ),
        ],
      ),
    );
  }

  @override
  Future<ChartResult<SubscriptionsAnnual>> subscriptionsAnnual(
    ChartFilter f,
  ) async {
    calls++;
    return const ChartNotEnoughData<SubscriptionsAnnual>(
      NotEnoughReason.noData,
      have: 0,
      need: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAccounts implements AccountsRepository {
  FakeAccounts([this.rows = const []]);
  final List<AccountWithBalances> rows;

  @override
  Future<List<AccountWithBalances>> listWithBalances({
    bool includeHidden = false,
  }) async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _t0 = DateTime(2026, 11, 1);

Account acct(AccountKind kind, {Money? limit}) => Account(
  id: 'a-${kind.code}',
  kind: kind,
  label: 'x',
  defaultCurrency: egp,
  isHidden: false,
  isDefaultCash: false,
  createdAt: _t0,
  updatedAt: _t0,
  creditLimit: limit,
);

ProviderContainer container(FakeCharts charts, {required bool flag}) {
  final c = ProviderContainer(
    overrides: [
      accountsRepositoryProvider.overrideWith((ref) async => FakeAccounts()),
      featureFlagProvider.overrideWith(
        (ref, f) => flag && f == FeatureFlag.smartRoi,
      ),
      chartRepositoryProvider.overrideWith((ref) async => charts),
      clockProvider.overrideWithValue(() => DateTime(2026, 11, 15, 12)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('flag off: nothing is queried and the list is empty', () async {
    final charts = FakeCharts();
    final c = container(charts, flag: false);
    expect(await c.read(roiSuggestionsProvider(egp).future), isEmpty);
    expect(charts.calls, 0);
  });

  test(
    'flag on: staples rule from the groceries category, per currency',
    () async {
      final charts = FakeCharts();
      final c = container(charts, flag: true);
      final r = await c.read(roiSuggestionsProvider(egp).future);
      expect(r.map((s) => s.rule), [RoiRule.bulkStaples]);
      expect(r.single.monthly, Money(egp, 420000));
      expect(r.single.year1Saving, Money(egp, 840000));
      // Window: 1 Aug .. 31 Oct 2026 (three complete months before November).
      expect(charts.lastPeriod!.from, CivilDate(2026, 8, 1));
      expect(charts.lastPeriod!.to, CivilDate(2026, 10, 31));
    },
  );

  test(
    'a currency without example figures gets nothing and no query',
    () async {
      final charts = FakeCharts();
      final c = container(charts, flag: true);
      expect(await c.read(roiSuggestionsProvider(usd).future), isEmpty);
      expect(charts.calls, 0);
    },
  );

  test('January window crosses the year boundary', () async {
    final charts = FakeCharts();
    final c = ProviderContainer(
      overrides: [
        accountsRepositoryProvider.overrideWith((ref) async => FakeAccounts()),
        featureFlagProvider.overrideWith((ref, f) => true),
        chartRepositoryProvider.overrideWith((ref) async => charts),
        clockProvider.overrideWithValue(() => DateTime(2027, 1, 5)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(roiSuggestionsProvider(egp).future);
    expect(charts.lastPeriod!.from, CivilDate(2026, 10, 1));
    expect(charts.lastPeriod!.to, CivilDate(2026, 12, 31));
  });

  test('category ids are catalog ids (sys:groceries)', () {
    expect(roiCategoryCode('sys:groceries'), 'groceries');
    expect(roiCategoryCode('groceries'), 'groceries');
    expect(roiCategoryCode(null), '');
  });

  test(
    'signals: categories, idle cash and card balance, per currency',
    () async {
      final charts = _CatCharts();
      final s = await roiSignalsFrom(
        charts,
        egp,
        DateTime(2026, 11, 15),
        accounts: [
          AccountWithBalances(acct(AccountKind.cash), [
            AccountBalance(
              accountId: 'a-cash',
              currency: egp,
              asOf: DateTime(2026, 10, 10),
              balance: Money(egp, 8000000),
            ),
            // Another currency never mixes in.
            AccountBalance(
              accountId: 'a-cash',
              currency: usd,
              asOf: DateTime(2026, 10, 10),
              balance: Money(usd, 999900),
            ),
          ]),
          AccountWithBalances(
            acct(AccountKind.credit, limit: Money(egp, 5000000)),
            [
              AccountBalance(
                accountId: 'a-credit',
                currency: egp,
                asOf: DateTime(2026, 11, 1),
                available: Money(egp, 4200000),
              ),
            ],
          ),
        ],
      );
      // 3-month totals: dining 9,000 -> 3,000/mo, transport 6,000 -> 2,000/mo.
      expect(s.deliveryMonthly, Money(egp, 300000));
      expect(s.commuteMonthly, Money(egp, 200000));
      expect(s.coffeeMonthly, isNull);
      expect(s.waterMonthly, isNull);
      // Cash 80,000; all spend 15,000 -> 5,000/mo; surplus 75,000.
      expect(s.cashOnHand, Money(egp, 8000000));
      expect(s.idleSurplus, Money(egp, 7500000));
      expect(s.idleDays, 36);
      // Owed = limit 50,000 - available 42,000.
      expect(s.cardBalance, Money(egp, 800000));
    },
  );
}

class _CatCharts extends FakeCharts {
  @override
  Future<ChartResult<CategoryDonut>> categoryDonut(
    ChartPeriod p,
    ChartFilter f,
  ) async => ChartReady(
    CategoryDonut(
      total: Money(f.currency, 1500000),
      slices: [
        CategorySlice(
          categoryId: 'sys:dining',
          amount: Money(f.currency, 900000),
          shareBp: 6000,
          count: 30,
        ),
        CategorySlice(
          categoryId: 'sys:transport',
          amount: Money(f.currency, 600000),
          shareBp: 4000,
          count: 20,
        ),
      ],
    ),
  );
}
