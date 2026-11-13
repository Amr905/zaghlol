// T-114: one card for any of the nine Gold charts. S-20 and S-21 both use
// it, so a chart looks and behaves the same in the list and in its detail.
// Loading, error and empty states follow the Free cards (T-107).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../budget/presentation/budget_providers_ui.dart';
import '../../domain/chart_models.dart';
import '../chart_detail.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'charts_providers.dart';
import 'gold_chart_bodies.dart';

/// The charts drawn by [GoldChartCard].
const Set<ChartId> goldChartIds = {
  ChartId.burnCurve,
  ChartId.fiftyThirtyTwenty,
  ChartId.dayHourPattern,
  ChartId.monthVsAverage,
  ChartId.installmentTimeline,
  ChartId.subscriptionsAnnual,
  ChartId.cardsSplit,
  ChartId.netWorth,
  ChartId.personalInflation,
};

String goldChartTitle(AppLocalizations l, ChartId id) => switch (id) {
  ChartId.burnCurve => l.insightsChartTitleBurnRate,
  ChartId.fiftyThirtyTwenty => l.insightsChartTitleRule503020,
  ChartId.dayHourPattern => l.insightsChartTitleWeekPattern,
  ChartId.monthVsAverage => l.insightsChartTitleVsAverage,
  ChartId.installmentTimeline => l.insightsChartTitleInstallments,
  ChartId.subscriptionsAnnual => l.insightsChartTitleSubscriptions,
  ChartId.cardsSplit => l.insightsChartTitleCards,
  ChartId.netWorth => l.insightsChartTitleNetWorth,
  ChartId.personalInflation => l.insightsChartTitleInflation,
  _ => '',
};

class GoldChartCard extends ConsumerWidget {
  const GoldChartCard({
    super.key,
    required this.chart,
    required this.code,
    this.showExplain = true,
  });
  final ChartId chart;
  final String code;

  /// The "Explain" entry (S-20); S-21 has its own explainer below.
  final bool showExplain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = goldChartTitle(l, chart);
    final money = chartMoneyOf(ref, context);
    String pct(int bp) => chartPercentBp(ref, context, bp);
    final lang = Localizations.localeOf(context).languageCode;
    String number(int n) => ref.watch(digitsModeProvider(lang)).render('$n');
    final arabic = lang == 'ar';
    final cats = ref.watch(categoryRowsProvider).value ?? const [];
    String nameOf(String? id) {
      for (final c in cats) {
        if (c.id == id) return arabic ? c.nameAr : c.nameEn;
      }
      return l.insightsChartsOtherSlice;
    }

    final context0 = l.insightsChartsContext(
      l.commonCardFilterAll,
      code,
      l.commonPeriodThisCycle,
    );

    Widget build0<T>(
      AsyncValue<ChartResult<T>> value,
      VoidCallback retry, {
      required String Function(T) summary,
      required Widget Function(T) body,
      bool Function(T)? isEmpty,
      String? emptyText,
    }) => value.when(
      loading: () => ChartSkeleton(title: title),
      error: (_, _) => ChartError(title: title, onRetry: retry),
      data: (r) {
        final trailing = showExplain
            ? ZButton(
                label: l.insightsChartsExplain,
                variant: ZButtonVariant.text,
                size: ZButtonSize.small,
                onPressed: () => openChartDetail(
                  context,
                  chart: chart,
                  code: code,
                  openExplainer: true,
                ),
              )
            : null;
        return switch (r) {
          ChartReady<T>(:final data) when isEmpty == null || !isEmpty(data) =>
            ChartCard(
              title: title,
              contextLine: context0,
              trailing: trailing,
              summary: summary(data),
              child: body(data),
            ),
          ChartReady<T>() => ChartCard(
            title: title,
            contextLine: context0,
            child: ChartMessage(text: emptyText ?? l.insightsChartsEmptyFilter),
          ),
          ChartNotEnoughData<T>(:final reason) => ChartCard(
            title: title,
            contextLine: context0,
            child: ChartMessage(
              text:
                  emptyText ??
                  (reason == NotEnoughReason.noData
                      ? l.insightsChartsEmptyFilter
                      : l.insightsChartsEmptyCycle),
            ),
          ),
        };
      },
    );

    switch (chart) {
      case ChartId.burnCurve:
        return build0(
          ref.watch(burnChartProvider(code)),
          () => ref.invalidate(burnChartProvider(code)),
          summary: (d) => BurnBody.summary(l, money, number, d),
          body: (d) => BurnBody(curve: d),
        );
      case ChartId.fiftyThirtyTwenty:
        return build0(
          ref.watch(rule503020ChartProvider(code)),
          () => ref.invalidate(rule503020ChartProvider(code)),
          summary: (d) => Rule503020Body.summary(l, pct, d),
          body: (d) => Rule503020Body(rule: d),
        );
      case ChartId.dayHourPattern:
        return build0(
          ref.watch(dayHourChartProvider(code)),
          () => ref.invalidate(dayHourChartProvider(code)),
          summary: (d) => WeekPatternBody.summary(l, lang, money, d),
          body: (d) => WeekPatternBody(pattern: d),
        );
      case ChartId.monthVsAverage:
        return build0(
          ref.watch(vsAverageChartProvider(code)),
          () => ref.invalidate(vsAverageChartProvider(code)),
          summary: (d) => VsAverageBody.summary(l, pct, nameOf, d),
          body: (d) => VsAverageBody(data: d, nameOf: nameOf),
        );
      case ChartId.installmentTimeline:
        return build0(
          ref.watch(installmentsChartProvider(code)),
          () => ref.invalidate(installmentsChartProvider(code)),
          summary: (d) => InstallmentsBody.summary(l, money, d),
          body: (d) => InstallmentsBody(months: d),
          isEmpty: (d) => d.isEmpty,
        );
      case ChartId.subscriptionsAnnual:
        return build0(
          ref.watch(subscriptionsChartProvider(code)),
          () => ref.invalidate(subscriptionsChartProvider(code)),
          summary: (d) => SubscriptionsBody.summary(l, money, d),
          body: (d) => SubscriptionsBody(data: d),
          isEmpty: (d) => d.items.isEmpty,
        );
      case ChartId.cardsSplit:
        return build0(
          ref.watch(cardsChartProvider(code)),
          () => ref.invalidate(cardsChartProvider(code)),
          summary: (d) => CardsBody.summary(l, pct, d),
          body: (d) => CardsBody(cards: d),
          isEmpty: (d) => d.isEmpty,
        );
      case ChartId.netWorth:
        return build0(
          ref.watch(netWorthChartProvider(code)),
          () => ref.invalidate(netWorthChartProvider(code)),
          summary: (d) => NetWorthBody.summary(l, money, d),
          body: (d) => NetWorthBody(points: d),
          emptyText: l.insightsChartsEmptyNetWorth,
        );
      case ChartId.personalInflation:
        return build0(
          ref.watch(inflationChartProvider(code)),
          () => ref.invalidate(inflationChartProvider(code)),
          summary: (d) => InflationBody.summary(l, pct, d),
          body: (d) => InflationBody(points: d),
          isEmpty: (d) => d.length < 2,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
