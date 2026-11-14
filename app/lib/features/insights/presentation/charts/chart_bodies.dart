// T-107: the four Free chart bodies. Colour never carries meaning alone:
// every series has a text legend, and every figure is also written out.
// fl_chart does not mirror itself, so in RTL the data is reversed to make
// time (and the slice order) run right to left.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../../budget/presentation/budget_view.dart';
import '../../domain/chart_models.dart';
import 'chart_card.dart';
import 'chart_format.dart';

bool _rtl(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

// ------------------------------------------------------------ 1 cash flow

/// Income and spend bars per cycle, plus the saved line of the latest one.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final shown = _rtl(context) ? points.reversed.toList() : points;
    final maxY = points
        .map((p) => math.max(p.income.minor, p.spend.minor))
        .fold<int>(1, math.max);
    final last = points.last;
    final pct = last.income.minor > 0
        ? (last.net.minor * 100 / last.income.minor).round()
        : null;
    final savedText = pct == null
        ? chartMoney(ref, context, last.net)
        : '${chartMoney(ref, context, last.net)} (${chartPercent(ref, context, pct)})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 160,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.1,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                barTouchData: BarTouchData(enabled: false),
                barGroups: [
                  for (var i = 0; i < shown.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: ZSpacing.xs,
                      barRods: [
                        BarChartRodData(
                          toY: shown[i].income.minor.toDouble(),
                          color: c.primary,
                          width: 10,
                          borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                        ),
                        BarChartRodData(
                          toY: shown[i].spend.minor.toDouble(),
                          color: c.text,
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
            LegendItem(color: c.primary, label: l.insightsLegendIncome),
            LegendItem(color: c.text, label: l.insightsLegendSpent),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          '${l.insightsLegendSaved}: $savedText',
          style: ZType.body.copyWith(color: c.text),
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
  const DonutBody({super.key, required this.donut, required this.nameOf});
  final CategoryDonut donut;
  final String Function(String? id) nameOf;

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
    final palette = [
      c.primary,
      c.accent,
      c.onPrimaryContainer,
      c.accentDark,
      c.textMuted,
      c.outline,
    ];
    final shown = _rtl(context) ? slices.reversed.toList() : slices;
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                pieTouchData: PieTouchData(enabled: false),
                sections: [
                  for (final s in shown)
                    PieChartSectionData(
                      value: s.amount.minor.toDouble(),
                      color: palette[slices.indexOf(s) % palette.length],
                      radius: 28,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        for (var i = 0; i < slices.length; i++)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
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
                    style: ZType.body.copyWith(color: c.text),
                  ),
                ),
                Flexible(
                  child: ZMoneyText(
                    text: chartMoney(ref, context, slices[i].amount),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Text(
                  chartPercentBp(ref, context, slices[i].bp),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
      ],
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
