// T-211 (CHARTS-V2): "In and out": per month, spending as a thin bar and
// income as a line with dots; the open month hatched as projected. A month
// without data is an empty (dashed) slot and breaks the line, so it never
// reads as zero spending.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/z_tokens.dart';
import '../../domain/trends_models.dart';
import '../charts/chart_palette.dart';

class InOutChart extends StatelessWidget {
  const InOutChart({
    super.key,
    required this.bars,
    required this.monthLabel,
    required this.semanticLabel,
    this.height = 190,
  });

  final List<InOutBar> bars;
  final String Function(InOutBar bar) monthLabel;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _InOutPainter(
            bars: bars,
            colors: ZColors.of(context),
            textDirection: dir,
            textScale: MediaQuery.textScalerOf(context),
            monthLabel: monthLabel,
          ),
        ),
      ),
    );
  }
}

class _InOutPainter extends CustomPainter {
  _InOutPainter({
    required this.bars,
    required this.colors,
    required this.textDirection,
    required this.textScale,
    required this.monthLabel,
  });

  final List<InOutBar> bars;
  final ZColors colors;
  final TextDirection textDirection;
  final TextScaler textScale;
  final String Function(InOutBar) monthLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final rtl = textDirection == TextDirection.rtl;
    const top = 12.0;
    final bottom = size.height - 24;
    var hi = 1;
    for (final b in bars) {
      if (!b.hasData) continue;
      hi = math.max(hi, math.max(b.incomeMinor, b.spendMinor));
    }
    // Headroom so the tallest value does not touch the top.
    hi = hi + hi ~/ 8;
    double y(int v) => bottom - (bottom - top) * v / hi;
    final slot = size.width / bars.length;
    final bw = math.min(24.0, slot * .5);
    final ink = colors.text;
    final incomeColor = ZChartColors.incomeOf(colors);

    final grid = Paint()
      ..color = colors.outline.withValues(alpha: .5)
      ..strokeWidth = 1;
    for (final f in const [.33, .66, 1.0]) {
      final gy = bottom - (bottom - top) * f;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final dots = <Offset?>[];
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final cx = slot * (rtl ? bars.length - 1 - i : i) + slot / 2;
      final open = b.projected || i == bars.length - 1;
      final tp = TextPainter(
        text: TextSpan(
          text: monthLabel(b),
          style: ZType.caption.copyWith(
            color: open ? colors.text : colors.textMuted,
            fontWeight: open ? FontWeight.w700 : null,
          ),
        ),
        textDirection: textDirection,
        textScaler: textScale,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot);
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height - 2));
      if (!b.hasData) {
        dots.add(null);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - bw / 2, bottom - 36, cx + bw / 2, bottom),
          const Radius.circular(5),
        );
        final p = Path()..addRRect(rect);
        final paint = Paint()
          ..color = colors.textMuted.withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (final m in p.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 6) {
            canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
          }
        }
        continue;
      }
      final sy = y(b.spendMinor);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(cx - bw / 2, sy, cx + bw / 2, math.max(bottom, sy + 2)),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      if (b.projected) {
        canvas.save();
        canvas.clipRRect(rect);
        canvas.drawRRect(rect, Paint()..color = ink.withValues(alpha: .12));
        final stripe = Paint()
          ..color = ink.withValues(alpha: .6)
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
        canvas.drawRRect(rect, Paint()..color = ink.withValues(alpha: .88));
      }
      dots.add(Offset(cx, y(b.incomeMinor)));
    }

    final line = Paint()
      ..color = incomeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    // Break the line at a month without data.
    Path? run;
    void flush() {
      if (run != null) canvas.drawPath(run!, line);
      run = null;
    }

    final byX = [...dots.whereType<Offset>()];
    for (final d in dots) {
      if (d == null) {
        flush();
        continue;
      }
      run == null
          ? run = (Path()..moveTo(d.dx, d.dy))
          : run!.lineTo(d.dx, d.dy);
    }
    flush();
    for (final d in byX) {
      canvas.drawCircle(d, 4.5, Paint()..color = colors.surface);
      canvas.drawCircle(d, 3, Paint()..color = incomeColor);
    }
  }

  @override
  bool shouldRepaint(_InOutPainter old) =>
      old.bars != bars ||
      old.colors != colors ||
      old.textDirection != textDirection ||
      old.textScale != textScale;
}
