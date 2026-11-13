// T-107: S-20 Charts segment (mockup 07). Four Free charts (cash flow,
// category donut, top merchants, budget progress), then the nine Gold charts
// as locked previews. Each card loads on its own; one failure never blanks
// the page. Amounts stay per currency: the chips switch currency, nothing
// is summed across them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_chip.dart';
import '../../../budget/presentation/budget_providers_ui.dart';
import '../../../budget/presentation/budget_view.dart';
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../domain/chart_models.dart';
import '../chart_detail.dart';
import 'chart_bodies.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'charts_providers.dart';
import 'gold_chart_card.dart';
import 'locked_chart_card.dart';

class ChartsScreen extends ConsumerWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currencies = ref.watch(chartsCurrenciesProvider);
    return currencies.when(
      loading: () => ListView(
        padding: _padding,
        children: [
          ChartSkeleton(title: l.insightsChartTitleCashFlow),
          ChartSkeleton(title: l.insightsChartTitleCategories),
        ],
      ),
      error: (_, _) => ListView(
        padding: _padding,
        children: [
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
        return ListView(
          padding: _padding,
          children: [
            if (list.length > 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
                child: Wrap(
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.sm,
                  children: [
                    for (final c in list)
                      ZChip(
                        label: c.code,
                        selected: c.code == code,
                        onTap: () => ref
                            .read(chartsCurrencyProvider.notifier)
                            .select(c.code),
                      ),
                  ],
                ),
              ),
            if (code == null) ...[
              ChartCard(
                title: l.insightsChartTitleCashFlow,
                child: ChartMessage(text: l.insightsChartsEmptyCycle),
              ),
              ChartCard(
                title: l.insightsChartTitleCategories,
                child: ChartMessage(text: l.insightsChartsEmptyCycle),
              ),
              ChartCard(
                title: l.insightsChartTitleMerchants,
                child: ChartMessage(text: l.insightsChartsEmptyCycle),
              ),
            ] else ...[
              _CashFlowCard(code: code),
              _DonutCard(code: code),
              _MerchantsCard(code: code),
              _BudgetCard(code: code),
            ],
            for (final id in lockedChartOrder)
              if (decideChart(ref.watch(entitlementStateProvider), id).allowed)
                if (code == null)
                  ChartCard(
                    title: goldChartTitle(l, id),
                    child: ChartMessage(text: l.insightsChartsEmptyCycle),
                  )
                else
                  GoldChartCard(chart: id, code: code)
              else
                LockedChartCard(title: goldChartTitle(l, id)),
          ],
        );
      },
    );
  }
}

const _padding = EdgeInsetsDirectional.fromSTEB(
  ZSpacing.screen,
  ZSpacing.sm,
  ZSpacing.screen,
  ZSpacing.xxl,
);

String _context(AppLocalizations l, String code) => l.insightsChartsContext(
  l.commonCardFilterAll,
  code,
  l.commonPeriodThisCycle,
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
              contextLine: _context(l, code),
              trailing: _ExplainButton(chart: ChartId.cashFlow, code: code),
              summary: CashFlowBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                data,
              ),
              child: CashFlowBody(points: data),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              contextLine: _context(l, code),
              child: ChartMessage(text: _emptyText(l, r)),
            ),
          },
        );
  }
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
              contextLine: _context(l, code),
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
              child: DonutBody(donut: data, nameOf: nameOf),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              contextLine: _context(l, code),
              child: ChartMessage(text: _emptyText(l, r)),
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
              contextLine: _context(l, code),
              trailing: _ExplainButton(chart: ChartId.topMerchants, code: code),
              summary: MerchantsBody.summary(
                l,
                (m) => chartMoney(ref, context, m),
                data,
              ),
              child: MerchantsBody(rows: data),
            ),
            ChartReady() => ChartCard(
              title: title,
              contextLine: _context(l, code),
              child: ChartMessage(text: l.insightsChartsEmptyFilter),
            ),
            ChartNotEnoughData() => ChartCard(
              title: title,
              contextLine: _context(l, code),
              child: ChartMessage(text: _emptyText(l, r)),
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
                contextLine: _context(l, code),
                child: ChartMessage(text: l.budgetOverviewEmptyTitle),
              );
            }
            return ChartCard(
              title: title,
              contextLine: _context(l, code),
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ZButton(
      label: l.insightsChartsExplain,
      variant: ZButtonVariant.text,
      size: ZButtonSize.small,
      onPressed: () => openChartDetail(
        context,
        chart: chart,
        code: code,
        openExplainer: true,
      ),
    );
  }
}
