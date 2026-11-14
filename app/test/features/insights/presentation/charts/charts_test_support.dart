// T-107 test support: synthetic chart data and provider overrides.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/presentation/budget_test_support.dart';

export '../../../budget/presentation/budget_test_support.dart';

ChartPeriod _p(int m) => ChartPeriod.month(2026, m);

List<CashFlowPoint> cashFlowPoints() => [
  for (var m = 5; m <= 10; m++)
    CashFlowPoint(
      period: _p(m),
      income: egpM(30000),
      spend: egpM(18000 + m * 500),
      isPartial: false,
    ),
];

CategoryDonut donutData() => CategoryDonut(
  total: egpM(1000),
  slices: [
    CategorySlice(categoryId: null, amount: egpM(600), shareBp: 6000, count: 5),
    CategorySlice(categoryId: 'x', amount: egpM(400), shareBp: 4000, count: 3),
  ],
);

List<MerchantSpend> merchants(int n) => [
  for (var i = 0; i < n; i++)
    MerchantSpend(
      merchantNorm: 'm$i',
      name: 'Shop $i',
      amount: egpM(1000 - i * 100),
      count: 2,
    ),
];

List<Override> chartOverrides({
  List<Currency>? currencies,
  ChartResult<List<CashFlowPoint>>? cashFlow,
  ChartResult<CategoryDonut>? donut,
  ChartResult<List<MerchantSpend>>? top,
  bool cashFlowError = false,
  bool loading = false,
}) {
  final cur = currencies ?? [egp];
  return [
    chartsCurrenciesProvider.overrideWith((ref) async => cur),
    categoryRowsProvider.overrideWith((ref) async => []),
    budgetScreenDataProvider.overrideWith(
      (ref) async => data([egpView(), usdView()]),
    ),
    cashFlowChartProvider.overrideWith((ref, code) async {
      if (cashFlowError) throw StateError('boom');
      return cashFlow ?? ChartReady(cashFlowPoints());
    }),
    donutChartProvider.overrideWith(
      (ref, code) async => donut ?? ChartReady(donutData()),
    ),
    merchantsChartProvider.overrideWith(
      (ref, code) async => top ?? ChartReady(merchants(5)),
    ),
  ];
}
