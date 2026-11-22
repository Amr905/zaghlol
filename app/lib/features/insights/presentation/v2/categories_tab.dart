// T-210 (CHARTS-V2): the Categories tab: title with total and count, a sort
// control, the stacked share strip, every category as a ranked bar row, the
// selected category's line with "Open transactions", and its six-period
// trend. Gate: the category chart's (`chart_gate.dart`).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/db/app_database.dart' show CategoryRow;
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../budget/presentation/budget_providers_ui.dart'
    show categoryRowsProvider;
import '../../../gold/application/gating.dart';
import '../../application/chart_gate.dart';
import '../../domain/category_tab_models.dart';
import '../../domain/chart_models.dart';
import '../../domain/overview_models.dart';
import '../charts/chart_card.dart';
import '../charts/chart_drill.dart';
import '../charts/chart_format.dart';
import '../charts/charts_providers.dart';
import '../charts/locked_chart_card.dart';
import 'all_charts_button.dart';
import 'categories_providers.dart';
import 'category_rows.dart';
import 'overview_providers.dart';
import 'pace_chart.dart' show paceLineColor;
import 'v2_card.dart';
import 'v2_format.dart';

const _padding = EdgeInsetsDirectional.fromSTEB(
  ZSpacing.screen,
  ZSpacing.sm,
  ZSpacing.screen,
  ZSpacing.fabClearance,
);

/// The display name of category [id] (null = uncategorized).
String categoryDisplayName(
  AppLocalizations l,
  List<CategoryRow> categories,
  String? id,
  bool arabic,
) {
  if (id == null) return l.transactionsListFilterUncategorized;
  for (final r in categories) {
    if (r.id == id) return arabic ? r.nameAr : r.nameEn;
  }
  return l.insightsChartsOtherSlice;
}

class CategoriesTab extends ConsumerStatefulWidget {
  const CategoriesTab({super.key});

  @override
  ConsumerState<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<CategoriesTab> {
  CategorySort _sort = CategorySort.amount;

  /// The selected row's key ([_key]); null = the first row.
  String? _selected;

  static String _key(String? id) => id ?? '_none';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final code = ref.watch(overviewCurrencyProvider);
    return code.when(
      loading: () => ListView(
        padding: _padding,
        children: [ChartSkeleton(title: l.insightsV2CatsTitle)],
      ),
      error: (_, _) => ListView(
        padding: _padding,
        children: [
          ChartError(
            title: l.insightsV2CatsTitle,
            onRetry: () => ref.invalidate(overviewCurrencyProvider),
          ),
        ],
      ),
      data: (cur) {
        final open = decideChart(
          ref.watch(entitlementStateProvider),
          ChartId.categoryDonut,
        ).allowed;
        return ListView(
          padding: _padding,
          children: [
            if (open)
              ..._content(context, cur)
            else
              LockedChartCard(title: l.insightsV2CatsTitle),
            const AllChartsButton(),
          ],
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, String code) {
    final l = AppLocalizations.of(context);
    final donut = ref.watch(donutChartProvider(code));
    return donut.when(
      loading: () => [ChartSkeleton(title: l.insightsV2CatsTitle)],
      error: (_, _) => [
        ChartError(
          title: l.insightsV2CatsTitle,
          onRetry: () => ref.invalidate(donutChartProvider(code)),
        ),
      ],
      data: (r) => switch (r) {
        ChartNotEnoughData() => [
          V2Card(
            title: l.insightsV2CatsTitle,
            child: ChartThinState(message: l.insightsThinNoData),
          ),
        ],
        ChartReady<CategoryDonut>(:final data) =>
          data.slices.isEmpty
              ? [
                  V2Card(
                    title: l.insightsV2CatsTitle,
                    child: ChartThinState(message: l.insightsThinNoData),
                  ),
                ]
              : _loaded(context, code, data),
      },
    );
  }

  List<Widget> _loaded(BuildContext context, String code, CategoryDonut donut) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final cats = ref.watch(categoryRowsProvider).value ?? const [];
    final previous = ref.watch(previousDonutProvider(code)).value;
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final others =
        ref.watch(otherCurrencySpendProvider(code)).value ?? const [];
    final cur = Currency.of(code);
    String nameOf(String? id) => categoryDisplayName(l, cats, id, arabic);
    final rows = sortCategoryRows(
      rankedCategories(donut, previous: previous),
      _sort,
      nameOf,
    );
    var scale = 0;
    for (final r in rows) {
      scale = math.max(scale, math.max(r.amount.minor, r.previousMinor));
    }
    final sel = rows.firstWhere(
      (r) => _key(r.categoryId) == _selected,
      orElse: () => rows.first,
    );
    final strip = shareStrip(rows);
    final total = chartMoney(ref, context, donut.total);
    final n = rows.length;

    void openDrill(CategoryRowData r) {
      if (resolved == null) return;
      openChartDrill(
        context,
        code: code,
        period: resolved.period,
        previous: resolved.previous,
        categoryIds: r.categoryId == null ? const {} : {r.categoryId!},
        includeUncategorized: r.categoryId == null,
      );
    }

    final tip = l.insightsV2CatsTip(
      sel.count,
      v2Digits(ref, context, sel.count),
      nameOf(sel.categoryId),
      isolate(chartMoney(ref, context, sel.amount)),
    );

    return [
      V2Card(
        title: l.insightsV2CatsTitle,
        subtitle: l.insightsV2CatsSub(
          n,
          v2Digits(ref, context, n),
          isolate(total),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in others)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
                child: Semantics(
                  label: a11yAmounts(
                    l,
                    l.insightsV2OtherCurrency(chartMoney(ref, context, m)),
                  ),
                  excludeSemantics: true,
                  child: Text(
                    l.insightsV2OtherCurrency(
                      isolate(chartMoney(ref, context, m)),
                    ),
                    key: Key('cats-other-${m.currency.code}'),
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _SortControl(
                sort: _sort,
                onChanged: (s) => setState(() => _sort = s),
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            _ShareStrip(segments: strip, nameOf: nameOf),
            const SizedBox(height: ZSpacing.sm),
            for (final r in rows)
              _SelectableRow(
                key: Key('cats-row-${_key(r.categoryId)}'),
                selected: identical(r, sel),
                child: CategoryBarRow(
                  row: r,
                  currency: cur,
                  scaleMinor: scale,
                  onTap: () => setState(() => _selected = _key(r.categoryId)),
                ),
              ),
          ],
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: c.zaghlolBg,
          borderRadius: BorderRadius.circular(ZRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.md,
            vertical: ZSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: a11yAmounts(l, tip),
                  excludeSemantics: true,
                  child: Text(
                    tip,
                    key: const Key('cats-tip'),
                    style: ZType.bodySmall.copyWith(
                      color: c.zaghlolText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: l.insightsV2CatsOpenTxns,
                excludeSemantics: true,
                child: InkWell(
                  key: const Key('cats-open-txns'),
                  onTap: resolved == null ? null : () => openDrill(sel),
                  borderRadius: BorderRadius.circular(ZRadius.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: ZSpacing.minTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: ZSpacing.sm,
                      ),
                      child: Center(
                        child: Text(
                          l.insightsV2CatsOpenTxns,
                          style: ZType.label.copyWith(
                            color: c.zaghlolText,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: ZSpacing.md),
      _TrendCard(
        code: code,
        categoryId: sel.categoryId,
        name: nameOf(sel.categoryId),
      ),
    ];
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    super.key,
    required this.selected,
    required this.child,
  });
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? c.primaryContainer.withValues(alpha: .4) : null,
        borderRadius: BorderRadius.circular(ZRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: ZSpacing.xs),
        child: child,
      ),
    );
  }
}

class _SortControl extends StatelessWidget {
  const _SortControl({required this.sort, required this.onChanged});
  final CategorySort sort;
  final ValueChanged<CategorySort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    String label(CategorySort s) => switch (s) {
      CategorySort.amount => l.insightsV2CatsSortAmount,
      CategorySort.change => l.insightsV2CatsSortChange,
    };
    return Semantics(
      button: true,
      label: l.insightsV2CatsSortA11y(label(sort)),
      excludeSemantics: true,
      child: PopupMenuButton<CategorySort>(
        key: const Key('cats-sort'),
        initialValue: sort,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final s in CategorySort.values)
            PopupMenuItem(
              value: s,
              key: Key('cats-sort-${s.name}'),
              child: Text(label(s)),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 18, color: c.primary),
              const SizedBox(width: ZSpacing.xs),
              Text(
                label(sort),
                key: const Key('cats-sort-label'),
                style: ZType.label.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareStrip extends ConsumerWidget {
  const _ShareStrip({required this.segments, required this.nameOf});
  final List<ShareSegment> segments;
  final String Function(String?) nameOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    String name(ShareSegment s) =>
        s.isOther ? l.insightsChartsOtherSlice : nameOf(s.categoryId);
    final list = [
      for (final s in segments)
        l.insightsV2CatsStripSeg(
          name(s),
          chartPercentBp(ref, context, s.shareBp),
        ),
    ].join('. ');
    final base = paceLineColor(c);
    return Semantics(
      container: true,
      label: l.insightsV2CatsStripA11y(list),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        child: SizedBox(
          height: 14,
          child: Row(
            key: const Key('cats-strip'),
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: math.max(segments[i].shareBp, 1),
                  child: DecoratedBox(
                    key: Key('cats-strip-$i'),
                    decoration: BoxDecoration(
                      color: segments[i].isOther
                          ? c.textMuted.withValues(alpha: .5)
                          : base.withValues(alpha: 1 - i * .13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({
    required this.code,
    required this.categoryId,
    required this.name,
  });
  final String code;
  final String? categoryId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final title = l.insightsV2CatsTrendTitle(name);
    final key = (code, categoryId);
    final trend = ref.watch(categoryTrendProvider(key));
    return trend.when(
      loading: () => ChartSkeleton(title: title),
      error: (_, _) => ChartError(
        title: title,
        onRetry: () => ref.invalidate(categoryTrendProvider(key)),
      ),
      data: (bars) {
        final cur = Currency.of(code);
        String period(CategoryTrendBar b) =>
            DateFormat.MMM(Localizations.localeOf(context).languageCode)
                .format(DateTime(b.period.to.year, b.period.to.month));
        String money(int m) => chartMoney(ref, context, Money(cur, m));
        final items = [
          for (final b in bars)
            b.inProgress
                ? l.insightsV2CatsTrendItemOpen(period(b), money(b.minor))
                : l.insightsV2CatsTrendItem(period(b), money(b.minor)),
        ].join('. ');
        final anyOpen = bars.any((b) => b.inProgress);
        return V2Card(
          title: title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                label: a11yAmounts(l, l.insightsV2CatsTrendA11y(name, items)),
                excludeSemantics: true,
                child: SizedBox(
                  key: const Key('cats-trend'),
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      bars: bars,
                      colors: c,
                      textDirection: Directionality.of(context),
                      textScale: MediaQuery.textScalerOf(context),
                      valueLabel: (m) => v2AxisMoney(ref, context, m, cur),
                      periodLabel: period,
                    ),
                  ),
                ),
              ),
              if (anyOpen)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
                  child: Text(
                    l.insightsV2CatsTrendOpen,
                    key: const Key('cats-trend-open'),
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.bars,
    required this.colors,
    required this.textDirection,
    required this.textScale,
    required this.valueLabel,
    required this.periodLabel,
  });

  final List<CategoryTrendBar> bars;
  final ZColors colors;
  final TextDirection textDirection;
  final TextScaler textScale;
  final String Function(int) valueLabel;
  final String Function(CategoryTrendBar) periodLabel;

  TextPainter _text(
    String s,
    Color color,
    double maxWidth, {
    bool bold = false,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: ZType.caption.copyWith(
        color: color,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
    ),
    textDirection: textDirection,
    textScaler: textScale,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final rtl = textDirection == TextDirection.rtl;
    final slot = size.width / bars.length;
    final bw = math.min(26.0, slot * .6);
    final top = 22.0;
    final bottom = size.height - 22;
    var hi = 1;
    for (final b in bars) {
      hi = math.max(hi, b.minor);
    }
    final fill = paceLineColor(colors);
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final cx = slot * (rtl ? bars.length - 1 - i : i) + slot / 2;
      final y = bottom - (bottom - top) * b.minor / hi;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - bw / 2, y, cx + bw / 2, math.max(bottom, y + 2)),
        const Radius.circular(5),
      );
      final last = i == bars.length - 1;
      if (b.inProgress) {
        canvas.drawRRect(rect, Paint()..color = fill.withValues(alpha: .25));
        canvas.drawRRect(
          rect,
          Paint()
            ..color = fill
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        canvas.drawRRect(
          rect,
          Paint()..color = fill.withValues(alpha: last ? 1 : .45),
        );
      }
      final v = _text(valueLabel(b.minor), colors.text, slot, bold: last);
      v.paint(canvas, Offset(cx - v.width / 2, y - v.height - 2));
      final m = _text(
        periodLabel(b),
        last ? colors.text : colors.textMuted,
        slot,
        bold: last,
      );
      m.paint(canvas, Offset(cx - m.width / 2, size.height - m.height));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.bars != bars ||
      old.colors != colors ||
      old.textDirection != textDirection ||
      old.textScale != textScale;
}
