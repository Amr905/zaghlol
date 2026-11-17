// T-107: the four Free chart bodies. Colour never carries meaning alone:
// every series has a text legend, and every figure is also written out.
// fl_chart does not mirror itself, so in RTL the data is reversed to make
// time (and the slice order) run right to left.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../../budget/presentation/budget_view.dart';
import '../../domain/chart_models.dart';
import '../../../categorization/presentation/category_tile.dart';
import '../../../../core/db/app_database.dart' show CategoryRow;
import '../../../../core/ui/z_card.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'chart_palette.dart';

bool _rtl(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

// ------------------------------------------------------------ 1 cash flow

/// Income, spend and saved bars per cycle, with the month under each group.
class CashFlowBody extends ConsumerWidget {
  const CashFlowBody({super.key, required this.points});
  final List<CashFlowPoint> points;

  /// The a11y summary for [points] (latest bucket).
  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<CashFlowPoint> points,
  ) {
    final p = points.last;
    return l.insightsChartA11yCashFlow(
      money(p.income),
      money(p.spend),
      money(p.net),
    );
  }

  /// Integer percent of [net] over [income], rounded half away from zero
  /// (no double: money rule).
  static int savedPercent(int net, int income) {
    final scaled = net.abs() * 100;
    final r = (scaled + income ~/ 2) ~/ income;
    return net < 0 ? -r : r;
  }

  /// "You saved X this month (38%)": the footnote of the latest bucket.
  static String footnote(
    AppLocalizations l,
    String Function(Money) money,
    String Function(int) percent,
    List<CashFlowPoint> points,
  ) {
    final last = points.last;
    final pct = last.income.minor > 0
        ? savedPercent(last.net.minor, last.income.minor)
        : null;
    return l.insightsChartsSavedFootnote(
      money(last.net),
      pct == null ? '' : percent(pct),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final shown = _rtl(context) ? points.reversed.toList() : points;
    final maxY = points
        .map((p) => math.max(p.income.minor, p.spend.minor))
        .fold<int>(1, math.max);
    String month(CashFlowPoint p) {
      final d = p.period.to;
      return DateFormat.MMMM(lang).format(DateTime(d.year, d.month));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.05,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        space: ZSpacing.sm,
                        child: Text(
                          month(shown[v.toInt()]),
                          style: ZType.caption.copyWith(color: c.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(enabled: false),
                barGroups: [
                  for (var i = 0; i < shown.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 3,
                      barRods: [
                        for (final (value, color) in [
                          (shown[i].income.minor, ZChartColors.income),
                          (shown[i].spend.minor, ZChartColors.spend),
                          (math.max(0, shown[i].net.minor), ZChartColors.saved),
                        ])
                          BarChartRodData(
                            toY: value.toDouble(),
                            color: color,
                            width: 10,
                            borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.lg,
          runSpacing: ZSpacing.xs,
          children: [
            LegendItem(
              color: ZChartColors.income,
              label: l.insightsLegendIncome,
            ),
            LegendItem(color: ZChartColors.spend, label: l.insightsLegendSpent),
            LegendItem(color: ZChartColors.saved, label: l.insightsLegendSaved),
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------- 2 category donut

class _Slice {
  const _Slice(this.name, this.amount, this.bp);
  final String name;
  final Money amount;
  final int bp;
}

/// Top five slices; the rest fold into one "Other" slice.
List<_Slice> _donutSlices(
  AppLocalizations l,
  CategoryDonut d,
  String Function(String? id) nameOf,
) {
  final sorted = [...d.slices]..sort((a, b) => b.amount.compareTo(a.amount));
  final head = sorted.take(5).toList();
  final tail = sorted.skip(5).toList();
  final out = [
    for (final s in head)
      _Slice(
        s.categoryId == null
            ? l.insightsChartsOtherSlice
            : nameOf(s.categoryId),
        s.amount,
        s.shareBp,
      ),
  ];
  if (tail.isNotEmpty) {
    out.add(
      _Slice(
        l.insightsChartsOtherSlice,
        tail.map((s) => s.amount).reduce((a, b) => a + b),
        tail.fold<int>(0, (n, s) => n + s.shareBp),
      ),
    );
  }
  return out;
}

class DonutBody extends ConsumerWidget {
  const DonutBody({
    super.key,
    required this.donut,
    required this.nameOf,
    this.large = false,
  });
  final CategoryDonut donut;
  final String Function(String? id) nameOf;

  /// S-21: the big ring alone (the category list sits below it).
  final bool large;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    String Function(int bp) percent,
    CategoryDonut donut,
    String Function(String? id) nameOf,
  ) {
    final s = _donutSlices(l, donut, nameOf).first;
    return l.insightsChartA11yCategories(
      s.name,
      money(s.amount),
      percent(s.bp),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final slices = _donutSlices(l, donut, nameOf);
    const palette = ZChartColors.ramp;
    // A ring is not mirrored: the largest slice starts at 12 o'clock and runs
    // clockwise in both directions (mockup 07/08).
    final shown = slices;
    final size = large ? 240.0 : 132.0;
    final ring = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                startDegreeOffset: 270,
                centerSpaceRadius: size * 0.33,
                pieTouchData: PieTouchData(enabled: false),
                sections: [
                  for (final s in shown)
                    PieChartSectionData(
                      value: s.amount.minor.toDouble(),
                      color: palette[slices.indexOf(s) % palette.length],
                      radius: size * 0.15,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.27),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.insightsChartsSpendLabel,
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                  ZMoneyText(
                    text: large
                        ? trimCurrency(chartMoney(ref, context, donut.total))
                        : chartMoney(ref, context, donut.total),
                    size: large ? ZMoneySize.display : ZMoneySize.title,
                  ),
                  if (large)
                    Text(
                      RegExp(r'ج\.م|[A-Z]{3}')
                              .firstMatch(chartMoney(ref, context, donut.total))
                              ?.group(0) ??
                          '',
                      style: ZType.caption.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (large) return Center(child: ring);
    final legend = Column(
      children: [
        for (var i = 0; i < math.min(3, slices.length); i++)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette[i % palette.length],
                    borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Expanded(
                  child: Text(
                    slices[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodySmall.copyWith(color: c.text),
                  ),
                ),
                const SizedBox(width: ZSpacing.xs),
                ZMoneyText(
                  text: trimCurrency(
                    chartMoney(ref, context, slices[i].amount),
                  ),
                  size: ZMoneySize.caption,
                ),
                const SizedBox(width: ZSpacing.sm),
                Text(
                  chartPercentBp(ref, context, slices[i].bp),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        if (donut.coveredEarlier != null && donut.coveredEarlier!.minor > 0)
          _CoveredEarlierNote(amount: donut.coveredEarlier!),
      ],
    );
    // Large text: stack the legend under the ring so nothing is squeezed.
    if (MediaQuery.textScalerOf(context).scale(16) > 18.5) {
      return Column(
        children: [
          ring,
          const SizedBox(height: ZSpacing.sm),
          legend,
        ],
      );
    }
    return Row(
      children: [
        ring,
        const SizedBox(width: ZSpacing.md),
        Expanded(child: legend),
      ],
    );
  }
}

/// S-21: the full category list under the big ring (name, share, amount),
/// each in its tinted tile. Also the legend of the ring.
class DonutRows extends ConsumerWidget {
  const DonutRows({
    super.key,
    required this.donut,
    required this.nameOf,
    required this.categories,
  });
  final CategoryDonut donut;
  final String Function(String? id) nameOf;
  final List<CategoryRow> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final sorted = [...donut.slices]
      ..sort((a, b) => b.amount.compareTo(a.amount));
    CategoryRow? cat(String? id) {
      for (final r in categories) {
        if (r.id == id) return r;
      }
      return null;
    }

    return ZCard(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.lg,
        vertical: ZSpacing.xs,
      ),
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.outline),
            Semantics(
              container: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    vertical: ZSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      CategoryTile(
                        iconKey: cat(sorted[i].categoryId)?.icon,
                        colorHex: cat(sorted[i].categoryId)?.color,
                      ),
                      const SizedBox(width: ZSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nameOf(sorted[i].categoryId),
                              style: ZType.titleSmall.copyWith(color: c.text),
                            ),
                            Text(
                              chartPercentBp(ref, context, sorted[i].shareBp),
                              style: ZType.caption.copyWith(color: c.textMuted),
                            ),
                          ],
                        ),
                      ),
                      ZMoneyText(
                        text: trimCurrency(
                          chartMoney(ref, context, sorted[i].amount),
                        ),
                        size: ZMoneySize.title,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (donut.coveredEarlier != null && donut.coveredEarlier!.minor > 0)
            _CoveredEarlierNote(amount: donut.coveredEarlier!),
        ],
      ),
    );
  }
}

/// Muted legend note: cash payments covered by an earlier withdrawal. Not a
/// slice and not part of the donut total.
class _CoveredEarlierNote extends ConsumerWidget {
  const _CoveredEarlierNote({required this.amount});
  final Money amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: ZSpacing.sm),
      child: Text(
        l.insightsCoveredEarlier(chartMoney(ref, context, amount)),
        style: ZType.caption.copyWith(color: c.textMuted),
      ),
    );
  }
}

// ---------------------------------------------------------- 6 top merchants

class MerchantsBody extends ConsumerWidget {
  const MerchantsBody({super.key, required this.rows});
  final List<MerchantSpend> rows;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<MerchantSpend> rows,
  ) => l.insightsChartA11yMerchants(rows.first.name, money(rows.first.amount));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final top = rows.map((r) => r.amount.minor).fold<int>(1, math.max);
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.name,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    ZMoneyText(text: chartMoney(ref, context, r.amount)),
                  ],
                ),
                const SizedBox(height: ZSpacing.xs),
                _Bar(fraction: r.amount.minor / top),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Container(
      height: 8,
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.pill),
      ),
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.02, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.primary,
            borderRadius: BorderRadius.circular(ZRadius.pill),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------ budget progress bars

class BudgetBody extends ConsumerWidget {
  const BudgetBody({super.key, required this.view, required this.isArabic});
  final CurrencyBudgetView view;
  final bool isArabic;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    CurrencyBudgetView v,
  ) => l.budgetOverviewOverall(money(v.spent), money(v.limit!));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final rows = [...view.rows]
      ..sort(
        (a, b) => (b.progress.percent ?? 0).compareTo(a.progress.percent ?? 0),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.budgetOverviewOverall(
            chartMoney(ref, context, view.spent),
            chartMoney(ref, context, view.limit!),
          ),
          style: ZType.body.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.xs),
        _Bar(fraction: (view.percent ?? 0).clamp(0, 100) / 100),
        for (final r in rows.take(3))
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isArabic ? r.nameAr : r.nameEn,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    Text(
                      chartPercent(ref, context, r.progress.percent ?? 0),
                      style: ZType.caption.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: ZSpacing.xs),
                _Bar(fraction: ((r.progress.percent ?? 0).clamp(0, 100)) / 100),
                if ((r.progress.percent ?? 0) >= budgetWarnPercent)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                    child: Text(
                      l.budgetOverviewStatusNear,
                      style: ZType.caption.copyWith(color: c.dangerText),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
