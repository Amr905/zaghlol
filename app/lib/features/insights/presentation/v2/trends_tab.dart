// T-211 (CHARTS-V2): the Trends tab: "In and out" (last 6 months), T-209's
// "Saved each month", then the "Day by day" heatmap. Gates follow
// `chart_gate.dart`: in and out and saved come from the cash-flow chart, the
// heatmap from the day/hour pattern; a closed card shows the locked card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../domain/chart_models.dart';
import '../../domain/trends_models.dart';
import '../charts/chart_card.dart';
import '../charts/chart_format.dart';
import '../charts/chart_palette.dart';
import '../charts/locked_chart_card.dart';
import 'all_charts_button.dart';
import 'heatmap_card.dart';
import 'in_out_chart.dart';
import 'overview_providers.dart';
import 'saved_months_chart.dart';
import 'trends_providers.dart';
import 'v2_card.dart';

const _padding = EdgeInsetsDirectional.fromSTEB(
  ZSpacing.screen,
  ZSpacing.sm,
  ZSpacing.screen,
  ZSpacing.fabClearance,
);

class TrendsTab extends ConsumerWidget {
  const TrendsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final code = ref.watch(overviewCurrencyProvider);
    return code.when(
      loading: () => ListView(
        padding: _padding,
        children: [ChartSkeleton(title: l.insightsV2TrendsInOutTitle)],
      ),
      error: (_, _) => ListView(
        padding: _padding,
        children: [
          ChartError(
            title: l.insightsV2TrendsInOutTitle,
            onRetry: () => ref.invalidate(overviewCurrencyProvider),
          ),
        ],
      ),
      data: (cur) {
        final state = ref.watch(entitlementStateProvider);
        final flowOpen = decideChart(
          state,
          ChartId.cashFlow,
          openToFree: ref.watch(chartsOpenToFreeProvider),
        ).allowed;
        final dayOpen = decideChart(
          state,
          ChartId.dayHourPattern,
          openToFree: ref.watch(chartsOpenToFreeProvider),
        ).allowed;
        return ListView(
          padding: _padding,
          children: [
            if (flowOpen) ...[
              InOutCard(code: cur),
              SavedMonthsCard(code: cur),
            ] else ...[
              LockedChartCard(title: l.insightsV2TrendsInOutTitle),
              LockedChartCard(title: l.insightsV2SavedTitle),
            ],
            if (dayOpen)
              HeatmapCard(code: cur)
            else
              LockedChartCard(title: l.insightsV2TrendsDayTitle),
            const AllChartsButton(),
          ],
        );
      },
    );
  }
}

class InOutCard extends ConsumerWidget {
  const InOutCard({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final r = ref.watch(inOutProvider(code));
    return r.when(
      loading: () => ChartSkeleton(title: l.insightsV2TrendsInOutTitle),
      error: (_, _) => ChartError(
        title: l.insightsV2TrendsInOutTitle,
        onRetry: () => ref.invalidate(inOutProvider(code)),
      ),
      data: (res) => V2Card(
        title: l.insightsV2TrendsInOutTitle,
        subtitle: l.insightsV2TrendsInOutSub,
        child: switch (res) {
          ChartNotEnoughData<List<InOutBar>>() => ChartThinState(
            message: l.insightsChartsEmptyCycle,
          ),
          ChartReady<List<InOutBar>>(:final data) => _InOutBody(
            code: code,
            bars: data,
          ),
        },
      ),
    );
  }
}

class _InOutBody extends ConsumerWidget {
  const _InOutBody({required this.code, required this.bars});
  final String code;
  final List<InOutBar> bars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cur = Currency.of(code);
    final lang = Localizations.localeOf(context).languageCode;
    String month(InOutBar b) =>
        DateFormat.MMM(lang).format(DateTime(b.to.year, b.to.month));
    String money(int m) => chartMoney(ref, context, Money(cur, m));
    final items = [
      for (final b in bars)
        if (!b.hasData)
          l.insightsV2TrendsInOutEmptyA11y(month(b))
        else if (b.projected)
          l.insightsV2TrendsInOutBarProjectedA11y(
            month(b),
            money(b.incomeMinor),
            money(b.spendMinor),
          )
        else
          l.insightsV2TrendsInOutBarA11y(
            month(b),
            money(b.incomeMinor),
            money(b.spendMinor),
          ),
    ];
    Widget key(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: ZSpacing.xs + 2),
        Text(text, style: ZType.caption.copyWith(color: c.textMuted)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InOutChart(
          bars: bars,
          monthLabel: month,
          semanticLabel: a11yAmounts(
            l,
            l.insightsV2TrendsInOutA11y(items.join('. ')),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        ExcludeSemantics(
          child: Wrap(
            spacing: ZSpacing.md,
            runSpacing: ZSpacing.xs,
            children: [
              key(
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: c.text,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                l.insightsV2TrendsLegendSpent,
              ),
              key(
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: ZChartColors.incomeOf(c),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                l.insightsV2TrendsLegendIncome,
              ),
              key(
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.textMuted, width: 1.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                l.insightsV2TrendsLegendProjected,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
