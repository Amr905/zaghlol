// T-211 (CHARTS-V2): providers behind the Trends tab. Widgets read these;
// none touches the DB.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/application/budget_providers.dart';
import '../../data/chart_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/trends_models.dart';
import '../charts/charts_providers.dart';
import 'overview_providers.dart' show savedBuckets;

/// The last six buckets of income and spend, the open one projected.
final inOutProvider =
    FutureProvider.family<ChartResult<List<InOutBar>>, String>((
      ref,
      code,
    ) async {
      final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final today = ref.watch(todayProvider);
      final repo = await ref.watch(chartRepositoryProvider.future);
      final r = await repo.cashFlow(
        savedBuckets(resolved, schedule),
        ChartFilter(currency: Currency.of(code)),
      );
      return switch (r) {
        ChartReady<List<CashFlowPoint>>(:final data) => ChartReady(
          inOutBars(data, today),
        ),
        ChartNotEnoughData<List<CashFlowPoint>>(
          :final reason,
          :final have,
          :final need,
        ) =>
          ChartNotEnoughData<List<InOutBar>>(reason, have: have, need: need),
      };
    }, name: 'inOutProvider');

/// The chosen period and the net spend of each of its days.
typedef HeatData = ({ChartPeriod period, List<int> daily, CivilDate today});

final heatDailyProvider = FutureProvider.family<HeatData, String>((
  ref,
  code,
) async {
  final resolved = await ref.watch(chartsResolvedPeriodProvider.future);
  final today = ref.watch(todayProvider);
  final repo = await ref.watch(chartRepositoryProvider.future);
  final daily = await repo.dailySpend(
    resolved.period,
    ChartFilter(currency: Currency.of(code)),
  );
  return (period: resolved.period, daily: daily, today: today);
}, name: 'heatDailyProvider');
