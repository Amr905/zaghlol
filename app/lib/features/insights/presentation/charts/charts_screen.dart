// T-107: S-20 Charts segment (mockup 07). Four Free charts (cash flow,
// category donut, top merchants, budget progress), then the nine Gold charts
// as locked previews. Each card loads on its own; one failure never blanks
// the page. Amounts stay per currency: the chips switch currency, nothing
// is summed across them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/settings/settings_providers.dart';
import '../../../../core/ui/z_banner.dart';
import '../../../../core/ui/z_currency_switcher.dart';
import '../../../budget/application/budget_providers.dart' show todayProvider;
import '../../../budget/presentation/budget_providers_ui.dart';
import '../../../budget/presentation/budget_view.dart';
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';
import '../../domain/chart_summary.dart' show donutTopCount;
import '../chart_detail.dart';
import 'chart_bodies.dart';
import 'chart_card.dart';
import 'chart_drill.dart';
import 'chart_overview.dart';
import 'chart_period_bar.dart';
import 'chart_period_text.dart';
import 'chart_format.dart';
import 'chart_thin.dart';
import 'charts_providers.dart';
import 'gold_chart_card.dart';
import 'locked_chart_card.dart';

class ChartsScreen extends ConsumerStatefulWidget {
  const ChartsScreen({super.key});

  @override
  ConsumerState<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends ConsumerState<ChartsScreen> {
  /// "All charts (12)" opened. The cards behind it are not built until then
  /// (NFR-PERF-04: a chart only queries when it is on screen).
  bool _all = false;

  Widget _extra(AppLocalizations l, ChartId id, String? code) {
    if (decideChart(ref.watch(entitlementStateProvider), id).allowed) {
      return code == null
          ? ChartCard(
              title: goldChartTitle(l, id),
              child: ChartMessage(text: l.insightsChartsEmptyCycle),
            )
          : GoldChartCard(chart: id, code: code);
    }
    return LockedChartCard(title: goldChartTitle(l, id));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final currencies = ref.watch(chartsCurrenciesProvider);
    return currencies.when(
      loading: () => ListView(
        padding: _padding,
        children: [
          const ChartPeriodBar(),
          ChartSkeleton(title: l.insightsChartTitleCashFlow),
          ChartSkeleton(title: l.insightsChartTitleCategories),
        ],
      ),
      error: (_, _) => ListView(
        padding: _padding,
        children: [
          const ChartPeriodBar(),
          ChartError(
            title: l.insightsTabsCharts,
            onRetry: () => ref.invalidate(chartsCurrenciesProvider),
          ),
        ],
      ),
      data: (list) {
        final chosen = ref.watch(chartsCurrencyProvider);
        final code = list.isEmpty
            ? null
            : list
                  .firstWhere((c) => c.code == chosen, orElse: () => list.first)
                  .code;
        // The main charts, most useful first; the rest sit behind the
        // "All charts" button.
        final rest = [
          for (final id in lockedChartOrder)
            if (id != ChartId.monthVsAverage) id,
        ];
        return ListView(
          padding: _padding,
          children: [
            const ChartPeriodBar(),
            if (list.length > 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
                child: ZCurrencySwitcher(
                  codes: [for (final c in list) c.code],
                  selected: code,
                  onSelected: (v) =>
                      ref.read(chartsCurrencyProvider.notifier).select(v),
                ),
              ),
            if (ref.watch(hideAmountsProvider))
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
                child: ZBanner(message: l.insightsChartsHiddenNote),
              ),
            if (code != null) ChartSummaryStrip(code: code),
            if (code == null) ...[
              ChartCard(
                title: l.insightsChartTitleCashFlow,
                child: ChartThinState(message: l.insightsChartsEmptyCycle),
              ),
              ChartCard(
                title: l.insightsChartTitleCategories,
                child: ChartThinState(message: l.insightsThinNoData),
              ),
              ChartCard(
                title: l.insightsChartTitleMerchants,
                child: ChartThinState(message: l.insightsThinNoData),
              ),
            ] else ...[
              _CashFlowCard(code: code),
              _DonutCard(code: code),
              _MerchantsCard(code: code),
              _BudgetCard(code: code),
            ],
            _extra(l, ChartId.monthVsAverage, code),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: Semantics(
                button: true,
                expanded: _all,
                child: OutlinedButton(
                  key: const Key('charts-all'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(ZSpacing.minTarget),
                    foregroundColor: c.primary,
                    side: BorderSide(color: c.primary),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(
                    _all
                        ? l.insightsChartsFewerCharts
                        : l.insightsChartsAllCharts(
                            ref
                                .watch(
                                  digitsModeProvider(
                                    Localizations.localeOf(context)
                                        .languageCode,
                                  ),
                                )
                                .render('$kAllChartsCount'),
                          ),
                    style: ZType.titleSmall.copyWith(color: c.primary),
                  ),
                ),
              ),
            ),
            if (_all)
              for (final id in rest) _extra(l, id, code),
          ],
        );
      },
    );
  }
}

/// Free charts plus the nine Gold ones: the "All charts (12)" count (budget
/// progress is a Free chart that sits in the main list).
const int kAllChartsCount = 12;

const _padding = EdgeInsetsDirectional.fromSTEB(
  ZSpacing.screen,
  ZSpacing.sm,
  ZSpacing.screen,
  ZSpacing.fabClearance,
);

String _emptyText(AppLocalizations l, ChartNotEnoughData<Object?> r) =>
    r.reason == NotEnoughReason.noData
    ? l.insightsChartsEmptyFilter
    : l.insightsChartsEmptyCycle;

class _CashFlowCard extends ConsumerWidget {
  const _CashFlowCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = l.insightsChartTitleCashFlow;
    final periodResolved = ref.watch(chartsResolvedPeriodProvider).value;
    final periodText = ChartPeriodText.of(context, ref);
    final bucketKind = periodResolved?.bucketKind ?? ChartBucketKind.month;
    final today = ref.watch(todayProvider);
    final digits = ref.watch(
      digitsModeProvider(Localizations.localeOf(context).languageCode),
    );
    final total = ref.watch(cashFlowTotalProvider(code));
    return ref
        .watch(cashFlowChartProvider(code))
        .when(
          loading: () => ChartSkeleton(title: title),
          error: (_, _) => ChartError(
            title: title,
            onRetry: () => ref.invalidate(cashFlowChartProvider(code)),
          ),
          data: (r) => switch (r) {
            ChartReady(:final data) => ChartCard(
              title: title,
              subtitle: _cashFlowSubtitle(
                l,
                periodText,
                periodResolved,
                bucketKind,
                data.length,
                digits.render('${data.length}'),
                open:
                    periodResolved != null && periodResolved.period.to >= today,
              ),
              footnote: periodResolved == null
                  ? null
                  : CashFlowBody.footnote(
                      l,
                      (m) => chartMoney(ref, context, m),
                      (p) => chartPercent(ref, context, p),
                      cashFlowPeriodPoints(total, data),
                      periodText.now(periodResolved),
                    ),
              trailing: _ExplainButton(chart: ChartId.cashFlow, code: code),
              summary: CashFlowBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                cashFlowPeriodPoints(total, data),
              ),
              child: CashFlowBody(
                points: data,
                bucketKind: bucketKind,
                lastIsOpen:
                    periodResolved != null && periodResolved.period.to >= today,
                onOpenBucket: (p) =>
                    openChartDrill(context, code: code, period: p),
              ),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              child: ChartNotEnough(result: r, fallback: _emptyText(l, r)),
            ),
          },
        );
  }
}

String _cashFlowSubtitle(
  AppLocalizations l,
  ChartPeriodText text,
  ResolvedChartPeriod? resolved,
  ChartBucketKind kind,
  int count,
  String countText, {
  required bool open,
}) {
  final span = kind == ChartBucketKind.month || kind == ChartBucketKind.cycle
      ? l.insightsChartsLastNMonths(countText)
      : text.bucketCount(kind, count);
  return open && resolved != null
      ? l.insightsChartsCashFlowSub(
          span,
          l.insightsChartsPeriodOpenNote(text.now(resolved)),
        )
      : span;
}

class _DonutCard extends ConsumerWidget {
  const _DonutCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = l.insightsChartTitleCategories;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final cats = ref.watch(categoryRowsProvider).value ?? const [];
    String nameOf(String? id) {
      for (final c in cats) {
        if (c.id == id) return arabic ? c.nameAr : c.nameEn;
      }
      return l.insightsChartsOtherSlice;
    }

    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final previous = ref.watch(previousDonutProvider(code)).value;
    final digits = ref.watch(
      digitsModeProvider(Localizations.localeOf(context).languageCode),
    );
    return ref
        .watch(donutChartProvider(code))
        .when(
          loading: () => ChartSkeleton(title: title),
          error: (_, _) => ChartError(
            title: title,
            onRetry: () => ref.invalidate(donutChartProvider(code)),
          ),
          data: (r) => switch (r) {
            ChartReady(:final data) => ChartCard(
              title: title,
              subtitle: l.insightsChartsCategoriesSub(
                digits.render('$donutTopCount'),
              ),
              trailing: _ExplainButton(
                chart: ChartId.categoryDonut,
                code: code,
              ),
              summary: DonutBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                (bp) => chartPercentBp(ref, context, bp),
                data,
                nameOf,
              ),
              child: DonutBody(
                donut: data,
                nameOf: nameOf,
                previous: previous,
                onOpenEntry: resolved == null
                    ? null
                    : (e) => openChartDrill(
                        context,
                        code: code,
                        period: resolved.period,
                        previous: resolved.previous,
                        categoryIds: {for (final id in e.memberIds) ?id},
                        includeUncategorized: e.memberIds.contains(null),
                      ),
              ),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              child: ChartNotEnough(result: r, fallback: _emptyText(l, r)),
            ),
          },
        );
  }
}

class _MerchantsCard extends ConsumerWidget {
  const _MerchantsCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = l.insightsChartTitleMerchants;
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    return ref
        .watch(merchantsChartProvider(code))
        .when(
          loading: () => ChartSkeleton(title: title),
          error: (_, _) => ChartError(
            title: title,
            onRetry: () => ref.invalidate(merchantsChartProvider(code)),
          ),
          data: (r) => switch (r) {
            ChartReady(:final data) when data.isNotEmpty => ChartCard(
              title: title,
              subtitle: l.insightsChartsMerchantsSub,
              trailing: _ExplainButton(chart: ChartId.topMerchants, code: code),
              summary: MerchantsBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                data,
              ),
              child: MerchantsBody(
                rows: data,
                onOpen: resolved == null
                    ? null
                    : (m) => openChartDrill(
                        context,
                        code: code,
                        period: resolved.period,
                        previous: resolved.previous,
                        merchantNorm: m.merchantNorm,
                        merchantName: m.name,
                      ),
              ),
            ),
            ChartReady() => ChartCard(
              title: title,
              child: ChartMessage(text: l.insightsChartsEmptyFilter),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              child: ChartNotEnough(result: r, fallback: _emptyText(l, r)),
            ),
          },
        );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = l.insightsTabsBudget;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return ref
        .watch(budgetScreenDataProvider)
        .when(
          loading: () => ChartSkeleton(title: title),
          error: (_, _) => ChartError(
            title: title,
            onRetry: () => ref.invalidate(budgetScreenDataProvider),
          ),
          data: (data) {
            CurrencyBudgetView? view;
            for (final v in data.currencies) {
              if (v.currency.code == code) view = v;
            }
            if (view == null || view.limit == null) {
              return ChartCard(
                title: title,
                child: ChartMessage(text: l.budgetOverviewEmptyTitle),
              );
            }
            final current =
                ref.watch(chartsResolvedPeriodProvider).value?.isCurrentCycle ??
                true;
            return ChartCard(
              title: title,
              footnote: current ? null : l.insightsChartsPeriodBudgetNote,
              summary: BudgetBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                view,
              ),
              child: BudgetBody(view: view, isArabic: arabic),
            );
          },
        );
  }
}

/// The "Explain" entry on a chart card: opens S-21 with the explainer open.
class _ExplainButton extends StatelessWidget {
  const _ExplainButton({required this.chart, required this.code});
  final ChartId chart;
  final String code;

  @override
  Widget build(BuildContext context) => ExplainLink(
    onTap: () =>
        openChartDetail(context, chart: chart, code: code, openExplainer: true),
  );
}
