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

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/settings/settings_providers.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../../budget/presentation/budget_view.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';
import '../../domain/chart_summary.dart';
import '../../../categorization/presentation/category_tile.dart';
import '../../../../core/db/app_database.dart' show CategoryRow;
import '../../../../core/ui/z_card.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'chart_overview.dart';
import 'chart_palette.dart';
import 'chart_period_text.dart';

bool _rtl(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

// ------------------------------------------------------------ 1 cash flow

/// Income and spent bars per bucket with a light value axis, the month under
/// each group and the open (current) bucket hatched. Tapping a bar shows its
/// figures and a link to its transactions.
class CashFlowBody extends ConsumerStatefulWidget {
  const CashFlowBody({
    super.key,
    required this.points,
    this.bucketKind = ChartBucketKind.month,
    this.lastIsOpen = false,
    this.onOpenBucket,
  });
  final List<CashFlowPoint> points;

  /// What one bar is (T-188): a day, a week or a month. Sets the label under
  /// the bar and how dense the bars and labels are.
  final ChartBucketKind bucketKind;

  /// The last bar is the current, unfinished period: drawn hatched.
  final bool lastIsOpen;

  /// "See the transactions" of a tapped bar. Null: no link.
  final ValueChanged<ChartPeriod>? onOpenBucket;

  /// The a11y summary for [points] (latest bucket).
  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<CashFlowPoint> points,
  ) {
    final p = CashFlowPoint.total(points);
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

  /// "You saved X over this month (38%)": the footnote of the whole period.
  /// [now] is the period as a phrase (`ChartPeriodText.now`).
  static String footnote(
    AppLocalizations l,
    String Function(Money) money,
    String Function(int) percent,
    List<CashFlowPoint> points,
    String now,
  ) {
    final last = CashFlowPoint.total(points);
    final pct = last.income.minor > 0
        ? savedPercent(last.net.minor, last.income.minor)
        : null;
    return l.insightsChartsSavedFootnote(
      money(last.net),
      pct == null ? '' : percent(pct),
      now,
    );
  }

  @override
  ConsumerState<CashFlowBody> createState() => _CashFlowBodyState();
}

class _CashFlowBodyState extends ConsumerState<CashFlowBody> {
  /// Index into [CashFlowBody.points] (logical order, not mirrored).
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final bucketKind = widget.bucketKind;
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final rtl = _rtl(context);
    final text = ChartPeriodText.of(context, ref);
    final hidden = ref.watch(hideAmountsProvider);
    final currency = points.first.income.currency;
    final shown = rtl ? points.reversed.toList() : points;
    final n = shown.length;
    final maxMinor = points
        .map((p) => math.max(p.income.minor, p.spend.minor))
        .fold<int>(0, math.max);
    final step = niceAxisStep(maxMinor);
    final top = axisTop(maxMinor, step);
    final digits = ref.watch(digitsModeProvider(lang));
    // Day bars carry a month cue ("25 Oct") on the first bar and on day 1,
    // so a period that spans two months reads clearly (F7).
    // FU-269: a period starting on the 30th/31st has its day 1 two bars
    // later; then only the day-1 bar keeps the cue so the labels don't touch.
    bool cue(CashFlowPoint p) {
      if (bucketKind != ChartBucketKind.day) return false;
      if (p.period.from.day == 1) return true;
      if (!identical(p, points.first)) return false;
      final near = points.take(4).skip(1);
      return !near.any((q) => q.period.from.day == 1);
    }

    String label(CashFlowPoint p) {
      final d = p.period.from;
      switch (bucketKind) {
        case ChartBucketKind.day:
          return cue(p)
              ? ZDateFormat.dayMonth(
                  DateTime(d.year, d.month, d.day),
                  lang,
                  digits,
                )
              : digits.render('${d.day}');
        case ChartBucketKind.week:
          return ZDateFormat.dayMonth(
            DateTime(d.year, d.month, d.day),
            lang,
            digits,
          );
        case ChartBucketKind.month:
        case ChartBucketKind.cycle:
          final e = p.period.to;
          return DateFormat.MMMM(lang).format(DateTime(e.year, e.month));
      }
    }

    final dense = n > 12;
    final labelEvery = n <= 8 ? 1 : (n / 6).ceil();
    // A cue bar always has its label; the regular ones near it give way.
    bool showLabel(int i) {
      if (cue(shown[i])) return true;
      if (i % labelEvery != 0) return false;
      for (var j = i - 2; j <= i + 2; j++) {
        if (j >= 0 && j < n && cue(shown[j])) return false;
      }
      return true;
    }

    final rodWidth = n <= 6
        ? 13.0
        : n <= 12
        ? 8.0
        : n <= 31
        ? 4.0
        : 3.0;
    final incomeColor = ZChartColors.incomeOf(c);
    final spendColor = c.text;
    final selected = _selected;
    final openLogical = widget.lastIsOpen ? points.length - 1 : -1;

    BarChartRodData rod(int logical, int value, Color color) {
      final open = logical == openLogical;
      final dim = selected != null && selected != logical;
      final base = dim ? color.withValues(alpha: 0.45) : color;
      return BarChartRodData(
        toY: value.toDouble(),
        color: open ? base.withValues(alpha: 0.4) : base,
        width: rodWidth,
        borderRadius: BorderRadius.circular(ZRadius.sm / 2),
        borderSide: open
            ? BorderSide(color: base, width: 1.5)
            : BorderSide.none,
        borderDashArray: open ? const [3, 3] : null,
      );
    }

    final axisSide = SideTitles(
      showTitles: !hidden,
      reservedSize: 44,
      interval: step.toDouble(),
      getTitlesWidget: (v, meta) => SideTitleWidget(
        meta: meta,
        space: ZSpacing.xs,
        child: Text(
          chartCompactMoney(ref, context, Money(currency, v.round())),
          style: ZType.caption.copyWith(color: c.textMuted, fontSize: 10),
        ),
      ),
    );
    final noTitles = const AxisTitles();
    final axis = AxisTitles(sideTitles: axisSide);

    final sel = selected == null ? null : points[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sel != null)
          _BarBubble(
            title: label(sel),
            range: text.range(sel.period),
            point: sel,
            onOpen: widget.onOpenBucket == null
                ? null
                : () => widget.onOpenBucket!(sel.period),
          ),
        SizedBox(
          height: 200,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BarChart(
              BarChartData(
                maxY: top.toDouble(),
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step.toDouble(),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: c.outline,
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: rtl ? axis : noTitles,
                  rightTitles: rtl ? noTitles : axis,
                  topTitles: noTitles,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        space: ZSpacing.sm,
                        child: showLabel(v.toInt())
                            ? Text(
                                label(shown[v.toInt()]),
                                style: ZType.caption.copyWith(
                                  color: c.textMuted,
                                  fontWeight:
                                      (rtl ? n - 1 - v.toInt() : v.toInt()) ==
                                          openLogical
                                      ? FontWeight.w700
                                      : null,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  handleBuiltInTouches: false,
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final g = response?.spot?.touchedBarGroupIndex;
                    setState(() {
                      if (g == null) {
                        _selected = null;
                      } else {
                        final logical = rtl ? n - 1 - g : g;
                        _selected = _selected == logical ? null : logical;
                      }
                    });
                  },
                ),
                barGroups: [
                  for (var i = 0; i < n; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: dense ? 1 : 3,
                      barRods: [
                        rod(
                          rtl ? n - 1 - i : i,
                          shown[i].income.minor,
                          incomeColor,
                        ),
                        rod(
                          rtl ? n - 1 - i : i,
                          shown[i].spend.minor,
                          spendColor,
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
            LegendItem(color: incomeColor, label: l.insightsLegendIncome),
            LegendItem(color: spendColor, label: l.insightsLegendSpent),
            if (widget.lastIsOpen)
              LegendItem(
                color: spendColor.withValues(alpha: 0.4),
                label: l.insightsChartsPartialLegend(label(points.last)),
              ),
          ],
        ),
        if (sel == null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
            child: Text(
              l.insightsChartsBarHint,
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

/// The figures of a tapped bar, with the link to its transactions.
class _BarBubble extends ConsumerWidget {
  const _BarBubble({
    required this.title,
    required this.range,
    required this.point,
    required this.onOpen,
  });
  final String title;
  final String range;
  final CashFlowPoint point;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    String m(Money v) => chartMoney(ref, context, v);
    final body = [
      l.insightsChartsBubbleIncome(m(point.income)),
      l.insightsChartsBubbleSpent(m(point.spend)),
      l.insightsChartsBubbleSaved(m(point.net)),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: a11yAmounts(l, '$title, $range. ${body.join('، ')}'),
        excludeSemantics: true,
        child: DecoratedBox(
          key: const Key('cashflow-bubble'),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(ZRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(ZSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($range)',
                  style: ZType.label.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.xs),
                Wrap(
                  spacing: ZSpacing.md,
                  children: [
                    for (final t in body)
                      Text(
                        '\u2068$t\u2069',
                        style: ZType.caption.copyWith(color: c.text),
                      ),
                  ],
                ),
                if (onOpen != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('cashflow-open'),
                      onPressed: onOpen,
                      child: Text(
                        l.insightsChartsSeeTransactionsA11y,
                        style: ZType.titleSmall.copyWith(color: c.primary),
                      ),
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

// --------------------------------------------------------- 2 category donut

/// The ring of the top five categories plus "Other", its legend (tap a row
/// or a slice to select it), the change chips against the previous period
/// and, for a selected slice, the link to its transactions.
class DonutBody extends ConsumerStatefulWidget {
  const DonutBody({
    super.key,
    required this.donut,
    required this.nameOf,
    this.large = false,
    this.previous,
    this.onOpenEntry,
  });
  final CategoryDonut donut;
  final String Function(String? id) nameOf;

  /// S-21: the big ring alone (the category list sits below it).
  final bool large;

  /// The donut of the period before, for the change chips.
  final CategoryDonut? previous;

  /// "See the N transactions" of a selected entry. Null: no link.
  final ValueChanged<DonutEntry>? onOpenEntry;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    String Function(int bp) percent,
    CategoryDonut donut,
    String Function(String? id) nameOf,
  ) {
    final s = topCategoriesPlusOther(donut).first;
    return l.insightsChartA11yCategories(
      s.isOther || s.categoryId == null
          ? l.insightsChartsOtherSlice
          : nameOf(s.categoryId),
      money(s.amount),
      percent(s.shareBp),
    );
  }

  @override
  ConsumerState<DonutBody> createState() => _DonutBodyState();
}

class _DonutBodyState extends ConsumerState<DonutBody> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final large = widget.large;
    final donut = widget.donut;
    final entries = topCategoriesPlusOther(donut, previous: widget.previous);
    String nameOf(DonutEntry e) => e.isOther || e.categoryId == null
        ? l.insightsChartsOtherSlice
        : widget.nameOf(e.categoryId);
    final palette = ZChartColors.rampOf(c);
    Color colorOf(int i) => palette[i % palette.length];
    final size = large ? 240.0 : 150.0;
    final selected = _selected;
    // A ring is not mirrored: the largest slice starts at 12 o'clock and runs
    // clockwise in both directions (mockup 07/08).
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
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final i = response?.touchedSection?.touchedSectionIndex;
                    setState(
                      () => _selected = i == null || i < 0 || i == selected
                          ? null
                          : i,
                    );
                  },
                ),
                sections: [
                  for (var i = 0; i < entries.length; i++)
                    PieChartSectionData(
                      value: entries[i].amount.minor.toDouble(),
                      color: colorOf(i),
                      radius: size * (selected == i ? 0.18 : 0.15),
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Padding(
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
                                .firstMatch(
                                  chartMoney(ref, context, donut.total),
                                )
                                ?.group(0) ??
                            '',
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (large) return Center(child: ring);

    Widget legendRow(int i) {
      final e = entries[i];
      final name = nameOf(e);
      final amount = trimCurrency(chartMoney(ref, context, e.amount));
      final percent = chartPercentBp(ref, context, e.shareBp);
      return Semantics(
        button: true,
        selected: selected == i,
        label: a11yAmounts(
          l,
          l.insightsChartsSliceRowA11y(
            name,
            amount,
            percent,
            e.isOther ? '' : changeA11y(ref, context, l, e.change),
          ),
        ),
        excludeSemantics: true,
        child: InkWell(
          key: Key('donut-row-$i'),
          borderRadius: BorderRadius.circular(ZRadius.sm),
          onTap: () => setState(() => _selected = selected == i ? null : i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Opacity(
              opacity: selected == null || selected == i ? 1 : 0.55,
              child: LayoutBuilder(
                builder: (context, box) {
                  final rowWidth = box.maxWidth.isFinite ? box.maxWidth : 200.0;
                  return Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colorOf(i),
                          borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodySmall.copyWith(color: c.text),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.xs),
                      // T-231: scales down instead of overflowing the row when
                      // amount and share are wide (found on the emulator).
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: rowWidth * 0.7),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ZMoneyText(
                                text: amount,
                                size: ZMoneySize.caption,
                              ),
                              const SizedBox(width: ZSpacing.sm),
                              Text(
                                percent,
                                style: ZType.caption.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    final legend = Column(
      children: [
        for (var i = 0; i < entries.length; i++) legendRow(i),
        if (donut.coveredEarlier != null && donut.coveredEarlier!.minor > 0)
          _CoveredEarlierNote(amount: donut.coveredEarlier!),
      ],
    );
    // Large text: stack the legend under the ring so nothing is squeezed.
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 18.5;
    final top = stacked
        ? Column(
            children: [
              ring,
              const SizedBox(height: ZSpacing.sm),
              legend,
            ],
          )
        : Row(
            children: [
              ring,
              const SizedBox(width: ZSpacing.md),
              Expanded(child: legend),
            ],
          );
    final canOpen = selected != null && widget.onOpenEntry != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        top,
        if (selected != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: DecoratedBox(
                key: const Key('donut-bubble'),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(ZRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\u2068${l.insightsChartsSliceBubble(nameOf(entries[selected]), chartMoney(ref, context, entries[selected].amount), chartPercentBp(ref, context, entries[selected].shareBp))}\u2069',
                        style: ZType.label.copyWith(color: c.text),
                      ),
                      if (canOpen)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const Key('donut-open'),
                            onPressed: () =>
                                widget.onOpenEntry!(entries[selected]),
                            child: Text(
                              l.insightsChartsSeeTransactions(
                                ref
                                    .watch(
                                      digitsModeProvider(
                                        Localizations.localeOf(context)
                                            .languageCode,
                                      ),
                                    )
                                    .render('${entries[selected].count}'),
                              ),
                              style: ZType.titleSmall.copyWith(
                                color: c.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.previous != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Wrap(
              spacing: ZSpacing.md,
              runSpacing: ZSpacing.xs,
              children: [
                for (final e in entries)
                  if (!e.isOther)
                    Semantics(
                      container: true,
                      excludeSemantics: true,
                      label: l.insightsChartsChipA11y(
                        nameOf(e),
                        changeA11y(ref, context, l, e.change),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nameOf(e),
                            style: ZType.caption.copyWith(color: c.text),
                          ),
                          const SizedBox(width: ZSpacing.xs),
                          ChangeChip(
                            change: e.change,
                            tone: toneOf(e.change, moreIsGood: false),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
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
  const MerchantsBody({super.key, required this.rows, this.onOpen, this.other});
  final List<MerchantSpend> rows;

  /// T-223: the tail beyond [rows], shown as a plain "Other" row.
  final ({Money amount, int count})? other;

  /// A tapped place opens its transactions. Null: rows are plain.
  final ValueChanged<MerchantSpend>? onOpen;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<MerchantSpend> rows,
  ) => l.insightsChartA11yMerchants(rows.first.name, money(rows.first.amount));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final all = [
      ...rows,
      if (other != null)
        MerchantSpend(
          merchantNorm: '',
          name: l.insightsChartsOtherSlice,
          amount: other!.amount,
          count: other!.count,
        ),
    ];
    final top = all.map((r) => r.amount.minor).fold<int>(1, math.max);
    return Column(
      children: [
        for (final r in all)
          Builder(
            builder: (context) {
              final count = l.insightsChartsPlaceCount(
                r.count,
                digits.render('${r.count}'),
              );
              final amount = chartMoney(ref, context, r.amount);
              final row = Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: ZSpacing.xs,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ZSpacing.minTarget,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          Text(
                            count,
                            style: ZType.caption.copyWith(color: c.textMuted),
                          ),
                          const SizedBox(width: ZSpacing.md),
                          ZMoneyText(text: amount),
                        ],
                      ),
                      const SizedBox(height: ZSpacing.xs),
                      _Bar(fraction: r.amount.minor / top),
                    ],
                  ),
                ),
              );
              if (onOpen == null || r.merchantNorm.isEmpty) return row;
              return Semantics(
                button: true,
                label: a11yAmounts(
                  l,
                  l.insightsChartsPlaceRowA11y(r.name, count, amount),
                ),
                excludeSemantics: true,
                child: InkWell(
                  key: Key('merchant-${r.merchantNorm}'),
                  borderRadius: BorderRadius.circular(ZRadius.sm),
                  onTap: () => onOpen!(r),
                  child: row,
                ),
              );
            },
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
            color: c.brightness == Brightness.dark ? c.brandMint : c.primary,
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
        Builder(
          builder: (context) {
            final overall = l.budgetOverviewOverall(
              chartMoney(ref, context, view.spent),
              chartMoney(ref, context, view.limit!),
            );
            return Text(
              overall,
              semanticsLabel: a11yAmounts(l, overall),
              style: ZType.body.copyWith(color: c.text),
            );
          },
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
