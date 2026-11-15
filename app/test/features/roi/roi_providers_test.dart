// T-169: Smart ROI providers: flag gate and signal mapping with a fake
// chart repository (synthetic figures).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
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

ProviderContainer container(FakeCharts charts, {required bool flag}) {
  final c = ProviderContainer(
    overrides: [
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
}
