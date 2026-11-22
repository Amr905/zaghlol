// T-211 (CHARTS-V2): "Day by day": a calendar heatmap of the chosen period,
// one cell per day, five sequential steps of one hue (a zero day is the
// lightest), week rows starting Saturday, a less-to-more legend and a caption
// naming the priciest weekday. A day opens that day's transactions. The grid
// is a Row per week, so RTL mirrors it with no branching.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../domain/chart_models.dart';
import '../../domain/trends_models.dart';
import '../charts/chart_card.dart';
import '../charts/chart_drill.dart';
import '../charts/chart_format.dart';
import '../charts/chart_palette.dart';
import '../charts/charts_providers.dart';
import '../../../../core/ui/amount_semantics.dart';
import 'trends_providers.dart';
import 'v2_card.dart';
import 'v2_format.dart';

/// The fill of heat [level] (0..4) on the card.
Color heatColor(ZColors c, int level) {
  if (level <= 0) return c.surfaceSunk;
  final base = ZChartColors.incomeOf(c);
  const alphas = [.0, .25, .5, .75, 1.0];
  return Color.alphaBlend(base.withValues(alpha: alphas[level]), c.surface);
}

class HeatmapCard extends ConsumerWidget {
  const HeatmapCard({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(heatDailyProvider(code));
    return data.when(
      loading: () => ChartSkeleton(title: l.insightsV2TrendsDayTitle),
      error: (_, _) => ChartError(
        title: l.insightsV2TrendsDayTitle,
        onRetry: () => ref.invalidate(heatDailyProvider(code)),
      ),
      data: (d) {
        final hasSpend = d.daily.any((v) => v > 0);
        return V2Card(
          title: l.insightsV2TrendsDayTitle,
          subtitle: l.insightsV2TrendsDaySub,
          child: hasSpend
              ? _Body(code: code, data: d)
              : ChartThinState(message: l.insightsChartsEmptyCycle),
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.code, required this.data});
  final String code;
  final HeatData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final grid = buildHeatGrid(data.period, data.daily, data.today);
    final cur = Currency.of(code);

    String dateText(CivilDate d) =>
        ZDateFormat.dayMonth(DateTime(d.year, d.month, d.day), lang, digits);
    String label(HeatDay d) {
      if (d.future) {
        return l.insightsV2TrendsDayCellFutureA11y(dateText(d.date));
      }
      if (d.minor <= 0) {
        return l.insightsV2TrendsDayCellNoSpendA11y(dateText(d.date));
      }
      return a11yAmounts(
        l,
        l.insightsV2TrendsDayCellA11y(
          dateText(d.date),
          chartMoney(ref, context, Money(cur, d.minor)),
        ),
      );
    }

    // Saturday-first weekday headers (2024-01-06 is a Saturday).
    final headers = [
      for (var i = 0; i < 7; i++)
        DateFormat.E(lang).format(DateTime(2024, 1, 6 + i)),
    ];

    final peak = ref.watch(dayHourChartProvider(code)).value;
    final elapsed = data.period.contains(data.today)
        ? data.today.difference(data.period.from) + 1
        : (data.today > data.period.to ? data.period.lengthDays : 0);
    final peakDay = peak is ChartReady<DayHourPattern>
        ? priciestWeekday(peak.data, elapsedDays: elapsed)
        : null;

    final cells = <Widget?>[
      for (var i = 0; i < grid.leading; i++) null,
      for (final d in grid.days) _cell(context, c, d, label(d)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    const gap = ZSpacing.xs + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l.insightsV2TrendsDayA11y(
            v2Digits(ref, context, grid.days.length),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  for (final h in headers)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: gap / 2,
                        ),
                        child: ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              h,
                              maxLines: 1,
                              style: ZType.caption.copyWith(color: c.textMuted),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: gap),
              for (var r = 0; r < cells.length ~/ 7; r++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: gap),
                  child: Row(
                    children: [
                      for (var k = 0; k < 7; k++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: gap / 2,
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: cells[r * 7 + k] ?? const SizedBox(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.xs),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                l.insightsV2TrendsDayLess,
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: ZSpacing.sm),
              for (var i = 0; i < kHeatLevels; i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsetsDirectional.only(end: ZSpacing.xs),
                  decoration: BoxDecoration(
                    color: heatColor(c, i),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              Text(
                l.insightsV2TrendsDayMore,
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
        if (peakDay != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              l.insightsV2TrendsDayPriciest(
                DateFormat.EEEE(lang).format(DateTime(2024, 1, peakDay)),
              ),
              key: const Key('heat-priciest'),
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, ZColors c, HeatDay d, String label) {
    final decoration = BoxDecoration(
      color: d.future ? null : heatColor(c, d.level),
      borderRadius: BorderRadius.circular(ZRadius.sm),
      border: d.future
          ? Border.all(color: c.outline, width: 1.5)
          : d.isToday
          ? Border.all(color: c.text, width: 2)
          : null,
    );
    if (d.future) {
      return Semantics(
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          key: Key('heat-${d.date.toIso()}'),
          decoration: decoration,
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('heat-${d.date.toIso()}'),
        borderRadius: BorderRadius.circular(ZRadius.sm),
        onTap: () => openChartDrill(
          context,
          code: code,
          period: ChartPeriod(d.date, d.date),
        ),
        child: Ink(decoration: decoration),
      ),
    );
  }
}
