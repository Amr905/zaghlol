// T-211 test support: synthetic data of the Trends tab.

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/trends_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/insights/presentation/v2/trends_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'v2_test_support.dart';

export 'v2_test_support.dart';

/// Spend of the 17 days 25 Oct .. 10 Nov (major units); some quiet days.
const _daily = [
  420,
  980,
  0,
  260,
  1650,
  1240,
  380,
  520,
  0,
  190,
  870,
  1900,
  450,
  330,
  300,
  260,
  980,
];

DayHourPattern _pattern() => DayHourPattern(
  byWeekday: {
    for (var d = 1; d <= 7; d++)
      d: DayHourCell(spend: egpM(d == 5 ? 4000 : 500), count: 3),
  },
  byHour: {
    for (var h = 0; h < 24; h++) h: DayHourCell(spend: egpM(0), count: 0),
  },
);

List<InOutBar> sampleInOut({bool emptyFirst = false}) {
  final income = [30000, 30000, 31000, 32000, 32000, 32000];
  final spent = [24800, 26900, 32400, 25200, 25600, 21200];
  return [
    for (var i = 0; i < 6; i++)
      InOutBar(
        from: CivilDate(2026, 6 + i, 1),
        to: CivilDate(2026, 6 + i, 28),
        incomeMinor: (emptyFirst && i == 0 ? 0 : income[i]) * 100,
        spendMinor: (emptyFirst && i == 0 ? 0 : spent[i]) * 100,
        hasData: !(emptyFirst && i == 0),
        projected: i == 5,
      ),
  ];
}

List<Override> trendsOverrides({
  CivilDate? today,
  bool emptyFirstMonth = false,
  bool loading = false,
  bool error = false,
  bool noSpend = false,
}) {
  final now = today ?? CivilDate(2026, 11, 10);
  final period = ChartPeriod(CivilDate(2026, 10, 25), CivilDate(2026, 11, 24));
  return [
    ...v2Overrides(),
    inOutProvider.overrideWith((ref, code) async {
      if (loading) {
        return Future<ChartResult<List<InOutBar>>>.delayed(
          const Duration(days: 1),
        );
      }
      if (error) throw StateError('boom');
      return ChartReady(sampleInOut(emptyFirst: emptyFirstMonth));
    }),
    heatDailyProvider.overrideWith((ref, code) async {
      if (loading) {
        return Future<HeatData>.delayed(const Duration(days: 1));
      }
      if (error) throw StateError('boom');
      return (
        period: period,
        daily: [
          for (var i = 0; i < 31; i++)
            noSpend || i >= _daily.length ? 0 : _daily[i] * 100,
        ],
        today: now,
      );
    }),
    dayHourChartProvider.overrideWith(
      (ref, code) async => ChartReady(_pattern()),
    ),
  ];
}

/// The light colours, for comparing cell fills.
abstract final class ZColorsProbe {
  static ZColors get light => ZColors.light;
}
