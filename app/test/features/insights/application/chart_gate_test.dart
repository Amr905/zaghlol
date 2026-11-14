// T-105 / FU-123: the Free "4 core charts" are the real chart set.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/application/chart_approx.dart';
import 'package:zaghlol/features/insights/application/chart_gate.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/wealth/domain/approx_view.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  const free = EntitlementState.free;
  final gold = () {
    final c = ProviderContainer();
    c
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    return c.read(entitlementStateProvider);
  }();

  test('Free opens cash flow, donut, top merchants and budget bars only', () {
    final open = [
      for (final id in ChartId.values)
        if (decideChart(free, id).allowed) id,
    ];
    expect(open, [
      ChartId.cashFlow,
      ChartId.categoryDonut,
      ChartId.topMerchants,
      ChartId.budgetProgress,
    ]);
    for (final id in ChartId.values) {
      if (!open.contains(id)) expect(decideChart(free, id).paywall, isTrue);
    }
  });

  test('Gold opens every chart; gate indexes are unique', () {
    for (final id in ChartId.values) {
      expect(decideChart(gold, id).allowed, isTrue, reason: '$id');
    }
    expect(
      {for (final id in ChartId.values) chartGateIndex(id)}.length,
      ChartId.values.length,
    );
  });

  test('top merchants: 5 for Free, the Gold limit for Gold', () {
    expect(topMerchantsLimitFor(free), 5);
    expect(topMerchantsLimitFor(gold), 10);
    expect(topMerchantsLimitFor(gold, goldLimit: 20), 20);
  });

  group('approximate view', () {
    final egp = Currency.of('EGP');
    final gbp = Currency.of('GBP');
    final empty = FxTable(const [], reportedStale: false);

    test('off by default: no combined figure exists', () {
      final v = approxChartTotal(
        enabled: false,
        perCurrency: [Money(egp, 100), Money(gbp, 5)],
        target: egp,
        rates: empty,
        nowMs: 0,
      );
      expect(v, isA<ApproxViewOff>());
    });

    test('on without a rate: the foreign currency is "not included"', () {
      final v = approxChartTotal(
        enabled: true,
        perCurrency: [Money(egp, 100), Money(gbp, 5)],
        target: egp,
        rates: empty,
        nowMs: 0,
      ) as ApproxViewOn;
      expect(v.excluded, [gbp]);
      expect(v.figure!.amount.minor, 100);
      expect(v.approximate, isTrue);
    });
  });
}
