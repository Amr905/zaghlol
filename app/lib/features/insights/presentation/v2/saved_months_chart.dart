// T-209 (CHARTS-V2): "saved each month": income minus spending as diverging
// bars (a loss hangs below the axis), the open month projected and hatched,
// the average as a dashed line with a label. [SavedMonthsChart] and
// [SavedMonthsCard] are reused by the Trends tab (T-211).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../domain/chart_models.dart';
import '../../domain/saved_months.dart';
import '../charts/chart_card.dart';
import '../charts/chart_format.dart';
import 'overview_providers.dart';
import 'pace_chart.dart' show paceLineColor;
import 'v2_card.dart';
import 'v2_format.dart';

class SavedMonthsChart extends StatelessWidget {
  const SavedMonthsChart({
    super.key,
    required this.months,
    required this.currency,
    required this.valueLabel,
    required this.monthLabel,
    required this.averageLabel,
    required this.semanticLabel,
    this.height = 190,
  });

  final SavedMonths months;
  final Currency currency;

  /// The label above a bar (already masked when amounts are hidden).
  final String Function(int minor) valueLabel;
  final String Function(SavedBar bar) monthLabel;

  /// The label on the average line; null hides the line.
  final String? averageLabel;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SavedPainter(
            months: months,
            colors: c,
            rtl: Directionality.of(context) == TextDirection.rtl,
            textDirection: Directionality.of(context),
            textScale: MediaQuery.textScalerOf(context),
            valueLabel: valueLabel,
            monthLabel: monthLabel,
            averageLabel: averageLabel,
          ),
        ),
      ),
    );
  }
}

class _SavedPainter extends CustomPainter {
  _SavedPainter({
    required this.months,
    required this.colors,
    required this.rtl,
    required this.textDirection,
    required this.textScale,
    required this.valueLabel,
    required this.monthLabel,
    required this.averageLabel,
  });

  final SavedMonths months;
  final ZColors colors;
  final bool rtl;
  final TextDirection textDirection;
  final TextScaler textScale;
  final String Function(int) valueLabel;
  final String Function(SavedBar) monthLabel;
  final String? averageLabel;

  TextPainter _text(
    String s,
    Color color, {
    FontWeight? weight,
    double? maxWidth,
  }) => TextPainter(
    text: TextSpan(
      text: s,
      style: ZType.caption.copyWith(color: color, fontWeight: weight),
    ),
    textDirection: textDirection,
    textScaler: textScale,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);

  @override
  void paint(Canvas canvas, Size size) {
    final bars = months.bars;
    if (bars.isEmpty) return;
    final top = 24.0;
    final bottom = size.height - 24;
    var lo = 0;
    var hi = 0;
    for (final b in bars) {
      lo = math.min(lo, b.netMinor);
      hi = math.max(hi, b.netMinor);
    }
    if (months.averageMinor != null) {
      hi = math.max(hi, months.averageMinor!);
      lo = math.min(lo, months.averageMinor!);
    }
    if (hi == lo) hi = lo + 1;
    double y(int v) => top + (bottom - top) * (hi - v) / (hi - lo);
    final slot = size.width / bars.length;
    final bw = math.min(26.0, slot * .6);
    final zero = y(0);
    final fill = paceLineColor(colors);
    final neg = colors.accent;

    // Average line.
    final avg = months.averageMinor;
    if (avg != null && averageLabel != null) {
      final ay = y(avg);
      final p = Path()
        ..moveTo(0, ay)
        ..lineTo(size.width, ay);
      final paint = Paint()
        ..color = colors.textMuted.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final m in p.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 8) {
          canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
        }
      }
      final tp = _text(
        averageLabel!,
        colors.textMuted,
        maxWidth: size.width * .6,
      );
      tp.paint(
        canvas,
        Offset(rtl ? size.width - 4 - tp.width : 4, ay - tp.height - 2),
      );
    }

    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final slotIndex = rtl ? bars.length - 1 - i : i;
      final cx = slot * slotIndex + slot / 2;
      final v = b.netMinor;
      final y0 = math.min(y(v), zero);
      final y1 = math.max(y(v), zero);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - bw / 2, y0, cx + bw / 2, math.max(y1, y0 + 2)),
        const Radius.circular(5),
      );
      final color = v >= 0 ? fill : neg;
      if (b.projected) {
        canvas.save();
        canvas.clipRRect(rect);
        canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: .25));
        final stripe = Paint()
          ..color = color
          ..strokeWidth = 3;
        for (var s = -rect.height; s < rect.width + rect.height; s += 6) {
          canvas.drawLine(
            Offset(rect.left + s, rect.bottom),
            Offset(rect.left + s + rect.height, rect.top),
            stripe,
          );
        }
        canvas.restore();
      } else {
        canvas.drawRRect(rect, Paint()..color = color);
      }
      final label = _text(
        (b.projected ? '~' : '') + valueLabel(v),
        colors.text,
        weight: FontWeight.w600,
        maxWidth: slot,
      );
      final ly = v >= 0 ? y0 - label.height - 2 : y1 + 2;
      label.paint(canvas, Offset(cx - label.width / 2, ly));
      final open = b.projected || i == bars.length - 1;
      final month = _text(
        monthLabel(b),
        open ? colors.text : colors.textMuted,
        weight: open ? FontWeight.w700 : null,
        maxWidth: slot,
      );
      month.paint(
        canvas,
        Offset(cx - month.width / 2, size.height - month.height - 2),
      );
    }
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = colors.textMuted.withValues(alpha: .5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SavedPainter old) =>
      old.months != months ||
      old.colors != colors ||
      old.rtl != rtl ||
      old.textScale != textScale ||
      old.averageLabel != averageLabel;
}

/// The month name of [bar] (a payday cycle is named after the month it ends in).
String savedMonthName(BuildContext context, SavedBar bar) =>
    DateFormat.MMM(Localizations.localeOf(context).languageCode)
        .format(DateTime(bar.to.year, bar.to.month));

/// The Overview / Trends card.
class SavedMonthsCard extends ConsumerWidget {
  const SavedMonthsCard({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final saved = ref.watch(savedMonthsProvider(code));
    return saved.when(
      loading: () => ChartSkeleton(title: l.insightsV2SavedTitle),
      error: (_, _) => ChartError(
        title: l.insightsV2SavedTitle,
        onRetry: () => ref.invalidate(savedMonthsProvider(code)),
      ),
      data: (r) => V2Card(
        title: l.insightsV2SavedTitle,
        subtitle: l.insightsV2SavedSub,
        child: switch (r) {
          ChartNotEnoughData<SavedMonths>() => ChartThinState(
            message: l.insightsChartsEmptyCycle,
          ),
          ChartReady<SavedMonths>(:final data) => _Body(
            code: code,
            months: data,
          ),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.code, required this.months});
  final String code;
  final SavedMonths months;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cur = Currency.of(code);
    String money(int minor) => chartMoney(ref, context, Money(cur, minor));
    final items = [
      for (final b in months.bars)
        b.projected
            ? l.insightsV2SavedBarProjectedA11y(
                savedMonthName(context, b),
                money(b.netMinor),
              )
            : l.insightsV2SavedBarA11y(
                savedMonthName(context, b),
                money(b.netMinor),
              ),
    ];
    return SavedMonthsChart(
      months: months,
      currency: cur,
      valueLabel: (m) => v2AxisMoney(ref, context, m, cur),
      monthLabel: (b) => savedMonthName(context, b),
      averageLabel: months.averageMinor == null
          ? null
          : l.insightsV2SavedAverage(
              v2AxisMoney(ref, context, months.averageMinor!, cur),
            ),
      semanticLabel: a11yAmounts(l, l.insightsV2SavedA11y(items.join('. '))),
    );
  }
}
