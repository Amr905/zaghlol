// T-209 (CHARTS-V2): the spending pace chart of the hero card. This period's
// cumulative line, the previous period as a thin dashed grey line, the budget
// as a dashed line, the projection dotted from today. Press and drag scrubs
// the line: a tooltip gives the day, the spend to date and last period's
// figure at that day. Direction aware: days run end-to-start in RTL and the
// value axis sits on the end side. Geometry may be double; money stays integer
// minor units until it is formatted by the caller.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/z_tokens.dart';
import '../../domain/chart_summary.dart' show niceAxisStep;
import '../../domain/pace.dart';

/// The line colour of this period: the brand mint on True Black, the primary
/// green on light.
Color paceLineColor(ZColors c) =>
    c.brightness == Brightness.dark ? c.brandMint : c.primary;

class PaceChart extends StatefulWidget {
  const PaceChart({
    super.key,
    required this.data,
    required this.axisLabel,
    required this.dayLabel,
    required this.firstDayLabel,
    required this.budgetLabel,
    required this.scrubSpent,
    required this.scrubLast,
    required this.semanticLabel,
    required this.semanticHint,
    this.height = 190,
  });

  final PaceData data;

  /// A value-axis label for [minor] (already masked when amounts are hidden).
  final String Function(int minor) axisLabel;
  final String Function(int day) dayLabel;
  final String Function(int day) firstDayLabel;

  /// The label on the budget line, e.g. "Budget 22K".
  final String? budgetLabel;

  /// Tooltip line 1 for a day, and line 2 (null without a previous period).
  final String Function(int day, int spentMinor) scrubSpent;
  final String Function(int previousMinor) scrubLast;
  final String semanticLabel;
  final String semanticHint;
  final double height;

  @override
  State<PaceChart> createState() => _PaceChartState();
}

class _PaceChartState extends State<PaceChart> {
  int? _day;

  static const double _axisW = 52;
  static const double _edge = 8;

  _Geometry _geometry(double w, bool rtl) => _Geometry(
    width: w,
    height: widget.height,
    rtl: rtl,
    axisW: _axisW,
    edge: _edge,
    data: widget.data,
  );

  void _scrub(double dx, double w, bool rtl) {
    final g = _geometry(w, rtl);
    final d = g.dayAt(dx).clamp(1, widget.data.elapsedDays);
    if (d != _day) setState(() => _day = d);
  }

  void _clear() {
    if (_day != null) setState(() => _day = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final data = widget.data;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final g = _geometry(w, rtl);
        final day = _day;
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          hint: widget.semanticHint,
          excludeSemantics: true,
          child: SizedBox(
            height: widget.height,
            width: w,
            child: GestureDetector(
              key: const Key('pace-chart'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _scrub(d.localPosition.dx, w, rtl),
              onHorizontalDragUpdate: (d) => _scrub(d.localPosition.dx, w, rtl),
              onHorizontalDragEnd: (_) => _clear(),
              onHorizontalDragCancel: _clear,
              onLongPressStart: (d) => _scrub(d.localPosition.dx, w, rtl),
              onLongPressMoveUpdate: (d) => _scrub(d.localPosition.dx, w, rtl),
              onLongPressEnd: (_) => _clear(),
              onTapDown: (d) => _scrub(d.localPosition.dx, w, rtl),
              onTapUp: (_) => _clear(),
              onTapCancel: _clear,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PacePainter(
                        g: g,
                        colors: c,
                        textDirection: Directionality.of(context),
                        scrubDay: day,
                        axisLabel: widget.axisLabel,
                        dayLabel: widget.dayLabel,
                        firstDayLabel: widget.firstDayLabel,
                        budgetLabel: widget.budgetLabel,
                        textScale: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                  if (day != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ExcludeSemantics(
                        child: Align(
                          // Physical alignment: the tooltip follows the line
                          // and stays inside the card.
                          alignment: Alignment(
                            (g.x(day) / w * 2 - 1).clamp(-1.0, 1.0),
                            -1,
                          ),
                          child: _Tip(
                            key: const Key('pace-tip'),
                            line1: widget.scrubSpent(
                              day,
                              data.cumulative[day - 1],
                            ),
                            line2: data.previousAt(day) == null
                                ? null
                                : widget.scrubLast(data.previousAt(day)!),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({super.key, required this.line1, this.line2});
  final String line1;
  final String? line2;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.text,
        borderRadius: BorderRadius.circular(ZRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.md,
          vertical: ZSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\u2068$line1\u2069',
              style: ZType.caption.copyWith(
                color: c.bg,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (line2 != null)
              Text(
                '\u2068$line2\u2069',
                style: ZType.caption.copyWith(
                  color: c.bg.withValues(alpha: .8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where things go: shared by the painter and the gesture code.
class _Geometry {
  _Geometry({
    required this.width,
    required this.height,
    required this.rtl,
    required double axisW,
    required double edge,
    required this.data,
  }) : plotLeft = rtl ? axisW : edge,
       plotRight = width - (rtl ? edge : axisW),
       plotTop = 14,
       plotBottom = height - 24 {
    var top = math.max(data.spent, data.previousCumulative.fold(0, math.max));
    top = math.max(
      top,
      math.max(data.budgetMinor ?? 0, data.projectedMinor ?? 0),
    );
    step = niceAxisStep(top);
    yMax = step * 3;
  }

  final double width;
  final double height;
  final bool rtl;
  final PaceData data;
  final double plotLeft;
  final double plotRight;
  final double plotTop;
  final double plotBottom;
  late final int step;
  late final int yMax;

  double get pw => plotRight - plotLeft;
  double get ph => plotBottom - plotTop;

  double _f(int day) =>
      data.periodDays <= 1 ? 0 : (day - 1) / (data.periodDays - 1);

  double x(int day) => rtl ? plotRight - _f(day) * pw : plotLeft + _f(day) * pw;

  double y(int minor) => plotTop + ph * (1 - minor / yMax);

  /// The day under the physical x [dx], clamped to the plot.
  int dayAt(double dx) {
    final f = ((rtl ? plotRight - dx : dx - plotLeft) / pw).clamp(0.0, 1.0);
    return (f * (data.periodDays - 1)).round() + 1;
  }
}

class _PacePainter extends CustomPainter {
  _PacePainter({
    required this.g,
    required this.colors,
    required this.textDirection,
    required this.scrubDay,
    required this.axisLabel,
    required this.dayLabel,
    required this.firstDayLabel,
    required this.budgetLabel,
    required this.textScale,
  });

  final _Geometry g;
  final ZColors colors;
  final TextDirection textDirection;
  final int? scrubDay;
  final String Function(int) axisLabel;
  final String Function(int) dayLabel;
  final String Function(int) firstDayLabel;
  final String? budgetLabel;
  final TextScaler textScale;

  TextPainter _text(String s, Color color, {FontWeight? weight}) => TextPainter(
    text: TextSpan(
      text: s,
      style: ZType.caption.copyWith(color: color, fontWeight: weight),
    ),
    textDirection: textDirection,
    textScaler: textScale,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final data = g.data;
    final line = paceLineColor(colors);
    final grid = Paint()
      ..color = colors.outline
      ..strokeWidth = 1;
    // Value axis: gridlines and labels on the end side.
    for (var i = 0; i <= 3; i++) {
      final v = g.step * i;
      final y = g.y(v);
      canvas.drawLine(Offset(g.plotLeft, y), Offset(g.plotRight, y), grid);
      final tp = _text(axisLabel(v), colors.textMuted);
      final dx = g.rtl ? g.plotLeft - 6 - tp.width : g.plotRight + 6;
      tp.paint(canvas, Offset(dx, y - tp.height / 2));
    }
    // Day axis.
    for (final d in paceDayTicks(data.periodDays)) {
      final tp = _text(
        d == 1 ? firstDayLabel(d) : dayLabel(d),
        d == data.elapsedDays ? colors.text : colors.textMuted,
      );
      final dx = (g.x(d) - tp.width / 2).clamp(0.0, g.width - tp.width);
      tp.paint(canvas, Offset(dx, g.height - tp.height - 2));
    }
    // Budget line.
    final budget = data.budgetMinor;
    if (budget != null) {
      final y = g.y(budget);
      _dashed(
        canvas,
        Path()
          ..moveTo(g.plotLeft, y)
          ..lineTo(g.plotRight, y),
        Paint()
          ..color = colors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
        2,
        4,
      );
      if (budgetLabel != null) {
        final tp = _text(
          budgetLabel!,
          colors.textMuted,
          weight: FontWeight.w600,
        );
        final dx = g.rtl ? g.plotRight - 4 - tp.width : g.plotLeft + 4;
        tp.paint(canvas, Offset(dx, y - tp.height - 2));
      }
    }
    // The previous period: thin, grey, dashed.
    if (data.previousCumulative.isNotEmpty) {
      final path = Path();
      final n = math.min(data.previousCumulative.length, data.periodDays);
      for (var d = 1; d <= n; d++) {
        final p = Offset(g.x(d), g.y(data.previousCumulative[d - 1]));
        d == 1 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      _dashed(
        canvas,
        path,
        Paint()
          ..color = colors.textMuted.withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        5,
        4,
      );
    }
    // This period: area and line.
    final pts = [
      for (var d = 1; d <= data.elapsedDays; d++)
        Offset(g.x(d), g.y(data.cumulative[d - 1])),
    ];
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    final area = Path.from(linePath)
      ..lineTo(pts.last.dx, g.y(0))
      ..lineTo(pts.first.dx, g.y(0))
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..color = line.withValues(
          alpha: colors.brightness == Brightness.dark ? .18 : .14,
        ),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Projection: dotted from today to the end.
    final proj = data.projectedMinor;
    if (proj != null) {
      final end = Offset(g.x(data.periodDays), g.y(proj));
      _dashed(
        canvas,
        Path()
          ..moveTo(pts.last.dx, pts.last.dy)
          ..lineTo(end.dx, end.dy),
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
        1,
        5,
      );
      canvas.drawCircle(end, 4, Paint()..color = colors.surface);
      canvas.drawCircle(
        end,
        4,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Today.
    canvas.drawCircle(pts.last, 6, Paint()..color = colors.surface);
    canvas.drawCircle(pts.last, 4.5, Paint()..color = line);
    // Scrub.
    final s = scrubDay;
    if (s != null) {
      final x = g.x(s);
      canvas.drawLine(
        Offset(x, g.plotTop),
        Offset(x, g.plotBottom),
        Paint()
          ..color = colors.text.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      final prev = data.previousAt(s);
      if (prev != null) {
        final o = Offset(x, g.y(prev));
        canvas.drawCircle(o, 4, Paint()..color = colors.surface);
        canvas.drawCircle(
          o,
          4,
          Paint()
            ..color = colors.textMuted
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      final o = Offset(x, g.y(data.cumulative[s - 1]));
      canvas.drawCircle(o, 6, Paint()..color = colors.surface);
      canvas.drawCircle(o, 4.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) =>
      old.g.data != g.data ||
      old.scrubDay != scrubDay ||
      old.colors != colors ||
      old.g.width != g.width ||
      old.g.rtl != g.rtl ||
      old.textScale != textScale ||
      old.budgetLabel != budgetLabel;
}

/// Strokes [path] as dashes: [on] long, [off] apart.
void _dashed(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      final end = math.min(d + on, m.length);
      canvas.drawPath(m.extractPath(d, end), paint);
      d += on + off;
    }
  }
}

/// A small legend swatch: a solid, dashed or dotted line.
class PaceSwatch extends StatelessWidget {
  const PaceSwatch({super.key, required this.color, required this.kind});
  final Color color;
  final PaceSwatchKind kind;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(18, 6),
      painter: _SwatchPainter(color, kind),
    ),
  );
}

enum PaceSwatchKind { solid, dashed, dotted }

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.kind);
  final Color color;
  final PaceSwatchKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = kind == PaceSwatchKind.solid ? 2.5 : 2;
    final path = Path()
      ..moveTo(1, size.height / 2)
      ..lineTo(size.width - 1, size.height / 2);
    switch (kind) {
      case PaceSwatchKind.solid:
        canvas.drawPath(path, p);
      case PaceSwatchKind.dashed:
        _dashed(canvas, path, p, 4, 3);
      case PaceSwatchKind.dotted:
        _dashed(canvas, path, p, 1, 4);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.kind != kind;
}
