// T-209 (CHARTS-V2): ranked horizontal category bars with a grey tick at the
// previous period's same-days amount and a change chip. [CategoryBarRow] is
// reused by the Categories tab (T-210); [WhereItWentCard] is the Overview card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../budget/presentation/budget_providers_ui.dart'
    show categoryRowsProvider;
import '../../../categorization/presentation/category_visuals.dart';
import '../../domain/chart_models.dart';
import '../../domain/overview_models.dart';
import '../charts/chart_card.dart';
import '../charts/chart_drill.dart';
import '../charts/chart_format.dart';
import '../charts/chart_overview.dart';
import '../charts/charts_providers.dart';
import 'pace_chart.dart' show paceLineColor;
import 'v2_card.dart';
import 'v2_format.dart';

/// One ranked row: icon, name, change chip, amount; under it a bar scaled to
/// [scaleMinor] with a tick at [CategoryRowData.previousMinor].
class CategoryBarRow extends ConsumerWidget {
  const CategoryBarRow({
    super.key,
    required this.row,
    required this.currency,
    required this.scaleMinor,
    required this.onTap,
  });

  final CategoryRowData row;
  final Currency currency;

  /// The amount a full-width bar stands for (the largest of the list).
  final int scaleMinor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final cats = ref.watch(categoryRowsProvider).value ?? const [];
    var name = l.insightsChartsOtherSlice;
    var icon = Icons.category_outlined;
    for (final r in cats) {
      if (r.id == row.categoryId) {
        name = arabic ? r.nameAr : r.nameEn;
        icon = iconFor(r.icon);
      }
    }
    final amount = chartMoney(ref, context, row.amount);
    final tone = toneOf(row.change, moreIsGood: false);
    final status = changeA11y(ref, context, l, row.change);
    final scale = scaleMinor <= 0 ? 1 : scaleMinor;
    double frac(int v) => (v / scale).clamp(0.0, 1.0);
    return Semantics(
      button: onTap != null,
      label: a11yAmounts(l, l.insightsV2CatRowA11y(name, amount, status)),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZRadius.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.primaryContainer,
                        borderRadius: BorderRadius.circular(ZRadius.md - 2),
                      ),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          icon,
                          size: 18,
                          color: c.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.md - 2),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.titleSmall.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    ChangeChip(change: row.change, tone: tone),
                    const SizedBox(width: ZSpacing.sm),
                    Text(
                      isolate(amount),
                      key: Key('cat-amount-${row.categoryId}'),
                      style: ZType.titleSmall.copyWith(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZSpacing.sm - 2),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 32 + ZSpacing.md - 2,
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = box.maxWidth;
                      return SizedBox(
                        height: 10,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.surfaceAlt,
                                  borderRadius: BorderRadius.circular(
                                    ZRadius.pill,
                                  ),
                                ),
                              ),
                            ),
                            PositionedDirectional(
                              start: 0,
                              top: 0,
                              bottom: 0,
                              width: w * frac(row.amount.minor),
                              child: DecoratedBox(
                                key: Key('cat-bar-${row.categoryId}'),
                                decoration: BoxDecoration(
                                  color: paceLineColor(c),
                                  borderRadius: BorderRadius.circular(
                                    ZRadius.pill,
                                  ),
                                ),
                              ),
                            ),
                            if (row.previousMinor > 0)
                              PositionedDirectional(
                                start: (w * frac(row.previousMinor) - 1).clamp(
                                  0.0,
                                  w - 2,
                                ),
                                top: -3,
                                bottom: -3,
                                width: 2,
                                child: DecoratedBox(
                                  key: Key('cat-tick-${row.categoryId}'),
                                  decoration: BoxDecoration(
                                    color: c.textMuted,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Overview card: the top four categories of the period.
class WhereItWentCard extends ConsumerWidget {
  const WhereItWentCard({
    super.key,
    required this.code,
    required this.onSeeAll,
    this.limit = 4,
  });
  final String code;
  final VoidCallback onSeeAll;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final donut = ref.watch(donutChartProvider(code));
    return donut.when(
      loading: () => ChartSkeleton(title: l.insightsV2CatTitle),
      error: (_, _) => ChartError(
        title: l.insightsV2CatTitle,
        onRetry: () => ref.invalidate(donutChartProvider(code)),
      ),
      data: (r) => V2Card(
        title: l.insightsV2CatTitle,
        subtitle: l.insightsV2CatSub,
        actionLabel: l.insightsV2CatSeeAll,
        actionKey: const Key('cat-see-all'),
        onAction: onSeeAll,
        child: switch (r) {
          ChartNotEnoughData() => ChartThinState(message: l.insightsThinNoData),
          ChartReady<CategoryDonut>(:final data) => _Rows(
            code: code,
            donut: data,
            limit: limit,
          ),
        },
      ),
    );
  }
}

class _Rows extends ConsumerWidget {
  const _Rows({required this.code, required this.donut, required this.limit});
  final String code;
  final CategoryDonut donut;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final previous = ref.watch(previousDonutProvider(code)).value;
    final rows = rankedCategories(donut, previous: previous, limit: limit);
    var scale = 0;
    for (final r in rows) {
      if (r.amount.minor > scale) scale = r.amount.minor;
      if (r.previousMinor > scale) scale = r.previousMinor;
    }
    return Column(
      children: [
        for (final r in rows)
          CategoryBarRow(
            row: r,
            currency: Currency.of(code),
            scaleMinor: scale,
            onTap: resolved == null
                ? null
                : () => openChartDrill(
                    context,
                    code: code,
                    period: resolved.period,
                    previous: resolved.previous,
                    categoryIds: r.categoryId == null
                        ? const {}
                        : {r.categoryId!},
                    includeUncategorized: r.categoryId == null,
                  ),
          ),
      ],
    );
  }
}
