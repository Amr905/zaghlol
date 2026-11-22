// T-210 (CHARTS-V2): the six-period trend of one category (null id =
// uncategorized) in one currency. Reads the existing category donut query per
// period; no new SQL.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/application/budget_providers.dart';
import '../../data/chart_providers.dart';
import '../../domain/category_tab_models.dart';
import '../../domain/chart_models.dart';
import '../charts/charts_providers.dart';
import 'overview_providers.dart' show savedBuckets;

/// The key of [categoryTrendProvider]: currency code and category id.
typedef CategoryTrendKey = (String code, String? categoryId);

final categoryTrendProvider =
    FutureProvider.family<List<CategoryTrendBar>, CategoryTrendKey>((
      ref,
      key,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final today = ref.watch(todayProvider);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final filter = ChartFilter(currency: Currency.of(key.$1));
      final out = <CategoryTrendBar>[];
      for (final p in savedBuckets(resolved, schedule)) {
        final r = await repo.categoryDonut(p, filter);
        var minor = 0;
        if (r case ChartReady<CategoryDonut>(:final data)) {
          for (final s in data.slices) {
            if (s.categoryId == key.$2) minor = s.amount.minor;
          }
        }
        out.add(
          CategoryTrendBar(
            period: p,
            minor: minor,
            inProgress: p.contains(today),
          ),
        );
      }
      return out;
    }, name: 'categoryTrendProvider');
