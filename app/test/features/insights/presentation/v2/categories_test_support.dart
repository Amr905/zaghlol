// T-210 test support: the Categories tab's data on top of the T-209 overrides.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/features/insights/domain/category_tab_models.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/v2/categories_providers.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'v2_test_support.dart';

export 'v2_test_support.dart';

/// Six periods of 3,200 .. 4,100 (the mockup's food trend), the last open.
List<CategoryTrendBar> sampleTrend() {
  const vals = [3200, 3500, 4300, 3800, 3650, 4100];
  return [
    for (var i = 0; i < 6; i++)
      CategoryTrendBar(
        period: ChartPeriod.month(2026, 6 + i),
        minor: vals[i] * 100,
        inProgress: i == 5,
      ),
  ];
}

List<Override> catsOverrides({
  ChartResult<CategoryDonut>? donut,
  CategoryDonut? previousDonut,
  List<CategoryTrendBar>? trend,
  bool trendError = false,
  void Function(String? id)? onTrend,
  List<Money> others = const [],
}) => [
  ...v2Overrides(donut: donut, previousDonut: previousDonut, others: others),
  categoryTrendProvider.overrideWith((ref, key) async {
    onTrend?.call(key.$2);
    if (trendError) throw StateError('boom');
    return trend ?? sampleTrend();
  }),
];
