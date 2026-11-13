// T-114: the nine Gold chart bodies (burn curve, 50/30/20, day pattern,
// month vs average, installments, subscriptions x12, cards split, net
// worth, personal inflation). Same rules as the Free bodies (T-107): colour
// never carries meaning alone (text legend + written figures), and fl_chart
// does not mirror itself, so in RTL the data order is reversed.
// Amounts stay in one currency; nothing here sums across currencies.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../domain/chart_models.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'charts_providers.dart';

bool _rtl(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl;

String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

String _digits(WidgetRef ref, BuildContext context, String s) =>
    ref.watch(digitsModeProvider(_lang(context))).render(s);

/// Horizontal progress bar (fraction 0..1) in the chart colours.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, this.color});
  final double fraction;
  final Color? color;

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
            color: color ?? c.primary,
            borderRadius: BorderRadius.circular(ZRadius.pill),
          ),
        ),
      ),
    );
  }
}

/// A line chart whose first point is at the start edge in either direction.
class _Line extends StatelessWidget {
  const _Line({required this.series, required this.maxX, this.minY = 0});

  /// Each series: (colour, dashed, ys by x = 0..).
  final List<({Color color, bool dashed, List<double> ys})> series;
  final int maxX;
  final double minY;

  @override
  Widget build(BuildContext context) {
    final rtl = _rtl(context);
    final top = series
        .expand((s) => s.ys)
        .fold<double>(1, (a, b) => math.max(a, b));
    return SizedBox(
      height: 160,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, maxX).toDouble(),
            minY: minY,
            maxY: top * 1.1,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < s.ys.length; i++)
                      FlSpot((rtl ? maxX - i : i).toDouble(), s.ys[i]),
                  ],
                  color: s.color,
                  barWidth: 3,
                  isCurved: false,
                  dotData: const FlDotData(show: false),
                  dashArray: s.dashed ? [6, 4] : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ 3 burn curve

class BurnBody extends ConsumerWidget {
  const BurnBody({super.key, required this.curve});
  final BurnCurve curve;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    String Function(int) number,
    BurnCurve c,
  ) => l.insightsChartA11yBurnRate(
    money(c.cumulative.last),
    c.budget == null ? money(c.cumulative.last) : money(c.budget!),
    number(c.elapsedDays),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final n = curve.elapsedDays;
    final hasBudget = curve.budget != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Line(
          maxX: curve.cycle.length - 1,
          series: [
            (
              color: c.text,
              dashed: false,
              ys: [for (final m in curve.cumulative) m.minor.toDouble()],
            ),
            if (hasBudget)
              (
                color: c.primary,
                dashed: true,
                ys: [
                  for (var d = 1; d <= curve.cycle.length; d++)
                    curve.idealAt(d)!.minor.toDouble(),
                ],
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.lg,
          runSpacing: ZSpacing.xs,
          children: [
            LegendItem(color: c.text, label: l.insightsLegendActual),
            if (hasBudget)
              LegendItem(color: c.primary, label: l.insightsLegendIdeal),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          '${l.insightsLegendToday}: '
          '${chartMoney(ref, context, curve.cumulative.last)}'
          '${hasBudget ? ' / ${chartMoney(ref, context, curve.budget!)}' : ''}'
          ' (${_digits(ref, context, '$n/${curve.cycle.length}')})',
          style: ZType.body.copyWith(color: c.text),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- 4 50/30/20

class Rule503020Body extends ConsumerWidget {
  const Rule503020Body({super.key, required this.rule});
  final FiftyThirtyTwenty rule;

  static String summary(
    AppLocalizations l,
    String Function(int bp) percent,
    FiftyThirtyTwenty r,
  ) => l.insightsChartA11yRule503020(
    percent(r.shareBp(r.needs)),
    percent(r.shareBp(r.wants)),
    percent(r.shareBp(r.savings)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final rows = [
      (
        l.insightsLegendNeeds,
        rule.needs,
        FiftyThirtyTwenty.targetNeedsBp,
        c.primary,
      ),
      (
        l.insightsLegendWants,
        rule.wants,
        FiftyThirtyTwenty.targetWantsBp,
        c.accent,
      ),
      (
        l.insightsLegendSavings,
        rule.savings,
        FiftyThirtyTwenty.targetSavingsBp,
        c.onPrimaryContainer,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.$1,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    ZMoneyText(text: chartMoney(ref, context, r.$2)),
                  ],
                ),
                const SizedBox(height: ZSpacing.xs),
                _Bar(fraction: rule.shareBp(r.$2) / 10000, color: r.$4),
                const SizedBox(height: ZSpacing.xs),
                Text(
                  '${chartPercentBp(ref, context, rule.shareBp(r.$2))}'
                  ' · ${l.insightsLegendTarget} '
                  '${chartPercentBp(ref, context, r.$3)}',
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------ 5 day/hour pattern

/// Saturday first (the Egyptian week), as ISO weekdays.
const List<int> _weekOrder = [6, 7, 1, 2, 3, 4, 5];

String _weekdayName(String lang, int iso, {bool short = false}) {
  // 2024-01-01 is a Monday.
  final d = DateTime(2024, 1, iso);
  return (short ? DateFormat.E(lang) : DateFormat.EEEE(lang)).format(d);
}

int _peakWeekday(DayHourPattern p) {
  var best = _weekOrder.first;
  for (final d in _weekOrder) {
    if (p.byWeekday[d]!.spend.minor > p.byWeekday[best]!.spend.minor) best = d;
  }
  return best;
}

class WeekPatternBody extends ConsumerWidget {
  const WeekPatternBody({super.key, required this.pattern});
  final DayHourPattern pattern;

  static String summary(
    AppLocalizations l,
    String lang,
    String Function(Money) money,
    DayHourPattern p,
  ) {
    final peak = _peakWeekday(p);
    final cell = p.byWeekday[peak]!;
    final avg = cell.count == 0
        ? cell.spend
        : Money(cell.spend.currency, cell.spend.minor ~/ cell.count);
    return l.insightsChartA11yWeekPattern(_weekdayName(lang, peak), money(avg));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final lang = _lang(context);
    final order = _rtl(context) ? _weekOrder.reversed.toList() : _weekOrder;
    final peak = _peakWeekday(pattern);
    final maxY = _weekOrder
        .map((d) => pattern.byWeekday[d]!.spend.minor)
        .fold<int>(1, math.max);
    return Column(
      children: [
        SizedBox(
          height: 140,
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
                  for (var i = 0; i < order.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: pattern.byWeekday[order[i]]!.spend.minor
                              .toDouble(),
                          color: order[i] == peak ? c.primary : c.textMuted,
                          width: 16,
                          borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.xs),
        Row(
          children: [
            // Same logical order as the bars; the Row mirrors in RTL.
            for (final d in _weekOrder)
              Expanded(
                child: Text(
                  _weekdayName(lang, d, short: true),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.caption.copyWith(
                    color: d == peak ? c.text : c.textMuted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            '${_weekdayName(lang, peak)}: '
            '${chartMoney(ref, context, pattern.byWeekday[peak]!.spend)}',
            style: ZType.body.copyWith(color: c.text),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------- 7 month vs average

class VsAverageBody extends ConsumerWidget {
  const VsAverageBody({super.key, required this.data, required this.nameOf});
  final MonthVsAverage data;
  final String Function(String? id) nameOf;

  static CategoryComparison? _biggestRise(MonthVsAverage d) {
    CategoryComparison? best;
    for (final c in d.byCategory) {
      if (c.deltaBp == null) continue;
      if (best == null || c.deltaBp! > best.deltaBp!) best = c;
    }
    return best;
  }

  static String summary(
    AppLocalizations l,
    String Function(int bp) percent,
    String Function(String? id) nameOf,
    MonthVsAverage d,
  ) {
    final b = _biggestRise(d);
    return l.insightsChartA11yVsAverage(
      b == null ? l.insightsLegendThisCycle : nameOf(b.categoryId),
      percent((b?.deltaBp ?? d.deltaBp) ?? 0),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final top = math.max(data.current.minor, data.average.minor);
    final cats = [
      ...data.byCategory,
    ]..sort((a, b) => (b.deltaBp?.abs() ?? 0).compareTo(a.deltaBp?.abs() ?? 0));
    Widget pair(String label, Money cur, Money avg, int? deltaBp) => Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: ZType.body.copyWith(color: c.text)),
              ),
              if (deltaBp != null)
                Text(
                  '${deltaBp > 0 ? '+' : ''}'
                  '${chartPercentBp(ref, context, deltaBp)}',
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
            ],
          ),
          const SizedBox(height: ZSpacing.xs),
          _Bar(fraction: cur.minor / math.max(1, top), color: c.primary),
          const SizedBox(height: ZSpacing.xs),
          _Bar(fraction: avg.minor / math.max(1, top), color: c.textMuted),
          const SizedBox(height: ZSpacing.xs),
          Text(
            '${chartMoney(ref, context, cur)} · '
            '${l.insightsLegendAverage} ${chartMoney(ref, context, avg)}',
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: ZSpacing.lg,
          runSpacing: ZSpacing.xs,
          children: [
            LegendItem(color: c.primary, label: l.insightsLegendThisCycle),
            LegendItem(color: c.textMuted, label: l.insightsLegendAverage),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        pair(
          l.insightsLegendThisCycle,
          data.current,
          data.average,
          data.deltaBp,
        ),
        for (final k in cats.take(3))
          pair(nameOf(k.categoryId), k.current, k.average, k.deltaBp),
      ],
    );
  }
}

// ------------------------------------------------------- 8 installments

class InstallmentsBody extends ConsumerWidget {
  const InstallmentsBody({super.key, required this.months});
  final List<InstallmentMonth> months;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<InstallmentMonth> m,
  ) => l.insightsChartA11yInstallments(money(m.first.total));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = _lang(context);
    final shown = _rtl(context) ? months.reversed.toList() : months;
    final maxY = months.map((m) => m.total.minor).fold<int>(1, math.max);
    String label(InstallmentMonth m) =>
        DateFormat.MMM(lang).format(DateTime(m.year, m.month));
    return Column(
      children: [
        SizedBox(
          height: 140,
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
                      barRods: [
                        BarChartRodData(
                          toY: shown[i].total.minor.toDouble(),
                          color: c.primary,
                          width: 16,
                          borderRadius: BorderRadius.circular(ZRadius.sm / 2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.xs),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Text(
                  label(m),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: LegendItem(
            color: c.primary,
            label: l.insightsLegendInstallments,
          ),
        ),
        for (final m in months)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label(m),
                    style: ZType.body.copyWith(color: c.text),
                  ),
                ),
                ZMoneyText(text: chartMoney(ref, context, m.total)),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------- 9 subscriptions x12

class SubscriptionsBody extends ConsumerWidget {
  const SubscriptionsBody({super.key, required this.data});
  final SubscriptionsAnnual data;

  static Money monthly(SubscriptionsAnnual d) =>
      Money(d.annualTotal.currency, d.annualTotal.minor ~/ 12);

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    SubscriptionsAnnual d,
  ) =>
      l.insightsChartA11ySubscriptions(money(monthly(d)), money(d.annualTotal));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final top = data.items.map((i) => i.annual.minor).fold<int>(1, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${l.insightsLegendMonthly}: '
                '${chartMoney(ref, context, monthly(data))}',
                style: ZType.body.copyWith(color: c.text),
              ),
            ),
          ],
        ),
        Text(
          '${l.insightsLegendYearly}: '
          '${chartMoney(ref, context, data.annualTotal)}',
          style: ZType.title.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        for (final i in data.items)
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
                        i.name,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    ZMoneyText(text: chartMoney(ref, context, i.annual)),
                  ],
                ),
                const SizedBox(height: ZSpacing.xs),
                _Bar(fraction: i.annual.minor / top),
                const SizedBox(height: ZSpacing.xs),
                Text(
                  chartMoney(ref, context, i.amount),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------- 10 cards split

class CardsBody extends ConsumerWidget {
  const CardsBody({super.key, required this.cards});
  final List<CardSpend> cards;

  static String summary(
    AppLocalizations l,
    String Function(int bp) percent,
    List<CardSpend> cards,
  ) =>
      l.insightsChartA11yCards(cards.first.label, percent(cards.first.shareBp));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final open = ref.watch(chartCardOpenerProvider);
    return Column(
      children: [
        for (final k in cards)
          Semantics(
            button: open != null,
            label: open == null
                ? null
                : l.insightsChartDetailCardRowA11y(
                    k.label,
                    chartMoney(ref, context, k.spend),
                  ),
            excludeSemantics: open != null,
            child: InkWell(
              onTap: open == null ? null : () => open(context, k.accountId),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ZSpacing.minTarget,
                ),
                child: Padding(
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
                              k.label,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.body.copyWith(color: c.text),
                            ),
                          ),
                          ZMoneyText(text: chartMoney(ref, context, k.spend)),
                          const SizedBox(width: ZSpacing.sm),
                          Text(
                            chartPercentBp(ref, context, k.shareBp),
                            style: ZType.caption.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: ZSpacing.xs),
                      _Bar(fraction: k.shareBp / 10000),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ 11 net worth

class NetWorthBody extends ConsumerWidget {
  const NetWorthBody({super.key, required this.points});
  final List<NetWorthPoint> points;

  static String summary(
    AppLocalizations l,
    String Function(Money) money,
    List<NetWorthPoint> p,
  ) => l.insightsChartA11yNetWorth(
    money(Money.fromStorage(p.first.netMinor, p.first.unit)),
    money(Money.fromStorage(p.last.netMinor, p.last.unit)),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final lows = points.map((p) => p.netMinor).reduce(math.min);
    final floor = lows < 0 ? lows.toDouble() * 1.1 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Line(
          maxX: points.length - 1,
          minY: floor,
          series: [
            (
              color: c.primary,
              dashed: false,
              ys: [for (final p in points) p.netMinor.toDouble()],
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        LegendItem(color: c.primary, label: l.insightsChartTitleNetWorth),
        const SizedBox(height: ZSpacing.xs),
        Text(
          '${chartMoney(ref, context, Money.fromStorage(points.first.netMinor, points.first.unit))}'
          ' → '
          '${chartMoney(ref, context, Money.fromStorage(points.last.netMinor, points.last.unit))}',
          style: ZType.body.copyWith(color: c.text),
        ),
      ],
    );
  }
}

// ------------------------------------------------------ 12 personal inflation

class InflationBody extends ConsumerWidget {
  const InflationBody({super.key, required this.points});
  final List<InflationPoint> points;

  static String summary(
    AppLocalizations l,
    String Function(int bp) percent,
    List<InflationPoint> p,
  ) => l.insightsChartA11yInflation(
    percent(p.first.indexBp),
    percent(p.last.indexBp),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final lang = _lang(context);
    String label(InflationPoint p) =>
        DateFormat.yMMM(lang).format(DateTime(p.year, p.month));
    final low = points.map((p) => p.indexBp).reduce(math.min);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Line(
          maxX: points.length - 1,
          minY: math.max(0, low * 0.9),
          series: [
            (
              color: c.primary,
              dashed: false,
              ys: [for (final p in points) p.indexBp.toDouble()],
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        LegendItem(color: c.primary, label: l.insightsChartTitleInflation),
        const SizedBox(height: ZSpacing.xs),
        Text(
          '${label(points.first)}: ${chartPercentBp(ref, context, points.first.indexBp)}'
          ' → '
          '${label(points.last)}: ${chartPercentBp(ref, context, points.last.indexBp)}',
          style: ZType.body.copyWith(color: c.text),
        ),
      ],
    );
  }
}
