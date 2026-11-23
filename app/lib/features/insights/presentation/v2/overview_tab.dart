// T-209 (CHARTS-V2): the Overview tab: hero pace card, the Zaghlol line,
// where it went, saved each month, coming up and "All charts (12)".
// Gates (CHARTS-V2): the hero and Coming up are free; the other cards follow
// `chart_gate.dart` for the chart they come from, with the locked card for
// free users.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_mascot_bubble.dart';
import '../../../gold/application/gating.dart';
import '../../../mascot/presentation/zaghlol_avatar.dart' show ZaghlolMoment;
import '../../application/chart_gate.dart';
import '../../domain/chart_models.dart';
import '../charts/chart_card.dart';
import '../charts/chart_overview.dart' show ChartOneLiner;
import '../charts/chart_period_text.dart';
import '../charts/charts_providers.dart';
import '../charts/locked_chart_card.dart';
import 'all_charts_button.dart';
import 'category_rows.dart';
import 'coming_up_card.dart';
import 'hero_pace_card.dart';
import 'overview_providers.dart';
import 'saved_months_chart.dart';

const _padding = EdgeInsetsDirectional.fromSTEB(
  ZSpacing.screen,
  ZSpacing.sm,
  ZSpacing.screen,
  ZSpacing.fabClearance,
);

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key, required this.onSeeAllCategories});

  /// "See all categories" switches the shell to the Categories tab.
  final VoidCallback onSeeAllCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final code = ref.watch(overviewCurrencyProvider);
    return code.when(
      loading: () => ListView(
        padding: _padding,
        children: [ChartSkeleton(title: l.insightsV2HeroLabel)],
      ),
      error: (_, _) => ListView(
        padding: _padding,
        children: [
          ChartError(
            title: l.insightsV2HeroLabel,
            onRetry: () => ref.invalidate(overviewCurrencyProvider),
          ),
        ],
      ),
      data: (cur) {
        final state = ref.watch(entitlementStateProvider);
        final donutOpen = decideChart(
          state,
          ChartId.categoryDonut,
          openToFree: ref.watch(chartsOpenToFreeProvider),
        ).allowed;
        final flowOpen = decideChart(
          state,
          ChartId.cashFlow,
          openToFree: ref.watch(chartsOpenToFreeProvider),
        ).allowed;
        return ListView(
          padding: _padding,
          children: [
            HeroPaceCard(code: cur),
            if (flowOpen) _ZaghlolLine(code: cur) else const SizedBox.shrink(),
            if (donutOpen)
              WhereItWentCard(code: cur, onSeeAll: onSeeAllCategories)
            else
              LockedChartCard(title: l.insightsV2CatTitle),
            if (flowOpen)
              SavedMonthsCard(code: cur)
            else
              LockedChartCard(title: l.insightsV2SavedTitle),
            ComingUpCard(code: cur),
            const AllChartsButton(),
          ],
        );
      },
    );
  }
}

/// The Zaghlol line: the existing one-liner of the summary strip (one or two
/// sentences), or the "nothing yet" bubble when the period is empty.
class _ZaghlolLine extends ConsumerWidget {
  const _ZaghlolLine({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final summary = ref.watch(chartSummaryProvider(code)).value;
    if (resolved == null || summary == null) return const SizedBox.shrink();
    if (summary.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
        child: ZMascotBubble(
          message: l.insightsSummaryEmpty,
          moment: ZaghlolMoment.thinking,
          avatarSize: 40,
        ),
      );
    }
    final text = ChartPeriodText.of(context, ref);
    return ChartOneLiner(
      code: code,
      summary: summary,
      prev: text.prevName(resolved),
    );
  }
}
