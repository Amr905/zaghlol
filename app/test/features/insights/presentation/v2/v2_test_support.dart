// T-209 test support: the Overview tab's synthetic data (the figures of the
// approved mockup, in minor units) and its provider overrides.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/core/db/app_database.dart' show CategoryRow;
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:zaghlol/features/insights/domain/overview_models.dart';
import 'package:zaghlol/features/insights/domain/pace.dart';
import 'package:zaghlol/features/insights/domain/saved_months.dart';
import 'package:zaghlol/features/insights/presentation/v2/overview_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../charts/charts_test_support.dart';

export '../charts/charts_test_support.dart';

/// Spend of each of the 20 days so far (major units, as in the mockup).
const _daily = [
  420, 980, 310, 260, 1650, 1240, 380, 520, 300, 190, //
  870, 1900, 450, 330, 300, 260, 980, 1250, 420, 640,
];

/// The previous period's cumulative spend (major units), 31 days.
const _lastCum = [
  600, 1100, 1900, 2500, 3900, 5300, 5700, 6300, 6900, 7400, 8500, 10200, //
  10800, 11200, 11800, 12300, 13300, 14600, 15200, 15900, 16500, 17300, 18300,
  19900, 21000, 21800, 22600, 23300, 24100, 24900, 25600,
];

List<int> _prevDaily() => [
  for (var i = 0; i < _lastCum.length; i++)
    (_lastCum[i] - (i == 0 ? 0 : _lastCum[i - 1])) * 100,
];

/// Day 20 of 31, a 22,000 budget unless [budget] is false.
PaceData samplePace({
  bool budget = true,
  bool previous = true,
  int elapsed = 20,
  bool closed = false,
  List<int>? daily,
}) => computePace(
  dailyThis: daily ?? [for (final d in _daily) d * 100],
  dailyPrev: previous ? _prevDaily() : const [],
  periodDays: 31,
  elapsedDays: elapsed,
  closed: closed,
  budgetMinor: budget ? 2200000 : null,
);

SavedMonths sampleSaved() {
  final nets = [5200, 3100, -1400, 6800, 6400];
  final bars = <SavedBar>[
    for (var i = 0; i < nets.length; i++)
      SavedBar(
        from: CivilDate(2026, 6 + i, 1),
        to: CivilDate(2026, 6 + i, 28),
        netMinor: nets[i] * 100,
        projected: false,
      ),
    SavedBar(
      from: CivilDate(2026, 11, 1),
      to: CivilDate(2026, 11, 30),
      netMinor: 1080000,
      projected: true,
    ),
  ];
  return SavedMonths(bars: bars, averageMinor: 400000);
}

List<UpcomingDue> sampleDues() => [
  for (final (i, d) in [
    ('WE internet', 13, 45000),
    ('valU instalment', 16, 120000),
    ('Gym', 19, 75000),
    ('Later', 22, 10000),
  ].indexed)
    UpcomingDue(
      itemId: 'u$i',
      name: d.$1,
      kind: 'bill',
      date: CivilDate(2026, 11, d.$2),
      amount: Money(egp, d.$3),
    ),
];

List<CategoryRow> sampleCategories() => [
  for (final (i, c) in const [
    ('food', 'Food & drink', 'أكل وشرب', 'x'),
    ('bills', 'Bills', 'فواتير', 'x'),
    ('transport', 'Transport', 'مواصلات', 'x'),
    ('shop', 'Shopping', 'تسوق', 'x'),
    ('misc', 'Other things', 'حاجات كده', 'x'),
  ].indexed)
    CategoryRow(
      id: c.$1,
      systemCode: null,
      parentId: null,
      nameAr: c.$3,
      nameEn: c.$2,
      icon: c.$4,
      color: '#000000',
      bucket: 'needs',
      isCustom: 0,
      isArchived: 0,
      sort: i,
    ),
];

List<Override> v2Overrides({
  PaceData? pace,
  List<Money> others = const [],
  List<UpcomingDue>? dues,
  ChartResult<SavedMonths>? saved,
  ChartResult<CategoryDonut>? donut,
  CategoryDonut? previousDonut,
  ChartSummary? summary,
  bool paceError = false,
  bool paceLoading = false,
  List<Currency>? currencies,
  void Function(String code)? onPace,
}) => [
  ...chartOverrides(
    donut: donut ?? ChartReady(categoryData()),
    previousDonut: previousDonut ?? categoryData(previous: true),
    summary: summary,
    currencies: currencies,
    categories: sampleCategories(),
  ),
  overviewCurrencyProvider.overrideWith((ref) async => 'EGP'),
  paceProvider.overrideWith((ref, code) async {
    onPace?.call(code);
    if (paceLoading) return Future<PaceData>.delayed(const Duration(days: 1));
    if (paceError) throw StateError('boom');
    return pace ?? samplePace();
  }),
  overviewTotalsProvider.overrideWith(
    (ref, code) async => PeriodTotals(income: egpM(32000), spend: egpM(13650)),
  ),
  otherCurrencySpendProvider.overrideWith((ref, code) async => others),
  savedMonthsProvider.overrideWith(
    (ref, code) async => saved ?? ChartReady(sampleSaved()),
  ),
  upcomingDuesProvider.overrideWith((ref, code) async => dues ?? sampleDues()),
];

/// Four named categories with the previous period's amounts.
CategoryDonut categoryData({bool previous = false}) {
  final now = {
    'food': 4100,
    'bills': 2900,
    'transport': 2300,
    'shop': 1950,
    'misc': 1600,
  };
  final before = {
    'food': 3650,
    'bills': 2900,
    'transport': 2500,
    'shop': 1500,
    'misc': 1450,
  };
  final m = previous ? before : now;
  return CategoryDonut(
    total: egpM(m.values.fold(0, (a, b) => a + b)),
    slices: [
      for (final e in m.entries)
        CategorySlice(
          categoryId: e.key,
          amount: egpM(e.value),
          shareBp: 2000,
          count: 3,
        ),
    ],
  );
}
