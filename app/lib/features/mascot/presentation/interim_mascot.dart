// T-099 interim mascot: animates the approved brand still
// (assets/mascot/zaghlol_still.png) with transforms and icon overlays. No new
// character art. Replaced automatically by RiveMascot when zaghlol.riv ships.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/z_tokens.dart';
import 'zaghlol_avatar.dart' show ZaghlolMoment, ZaghlolAvatar;
import 'zaghlol_mascot.dart';

class InterimMascot extends ZaghlolMascot {
  const InterimMascot({
    super.key,
    required super.moment,
    super.talk = false,
    required super.size,
  });

  @override
  State<InterimMascot> createState() => _InterimMascotState();
}

class _InterimMascotState extends State<InterimMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(InterimMascot old) {
    super.didUpdateWidget(old);
    if (old.moment != widget.moment) _start();
  }

  void _start() {
    _c.duration = widget.moment.duration;
    _c.value = 0;
    if (widget.moment.loops) {
      _c.repeat();
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ZColors>() ?? ZColors.light;
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final p = _pose(widget.moment, t, s);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(p.dx, p.dy),
              child: Transform.rotate(
                angle: p.rot,
                child: Transform.scale(
                  scale: p.scale,
                  child: Image.asset(
                    ZaghlolAvatar.stillAsset,
                    width: s,
                    height: s,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            ..._overlays(widget.moment, t, s, colors),
          ],
        );
      },
    );
  }
}

class _Pose {
  const _Pose({this.dx = 0, this.dy = 0, this.rot = 0, this.scale = 1});
  final double dx, dy, rot, scale;
}

const _tau = 2 * math.pi;

_Pose _pose(ZaghlolMoment m, double t, double s) {
  final arc = math.sin(math.pi * t); // 0 -> 1 -> 0
  final fade = 1 - t;
  switch (m) {
    case ZaghlolMoment.tourGuide:
      return _Pose(rot: 0.08 * math.sin(_tau * 2 * t) * fade);
    case ZaghlolMoment.proud:
    case ZaghlolMoment.saved:
      return _Pose(dy: -0.12 * s * arc, scale: 1 + 0.05 * arc);
    case ZaghlolMoment.shocked:
      return _Pose(
        dx: 0.03 * s * math.sin(_tau * 6 * t) * fade,
        scale: 1 + 0.08 * arc,
      );
    case ZaghlolMoment.detective:
      return _Pose(rot: 0.07 * math.sin(_tau * t) * arc);
    case ZaghlolMoment.professor:
      return _Pose(dy: 0.03 * s * math.sin(_tau * 2 * t) * arc);
    case ZaghlolMoment.listening:
      return _Pose(scale: 1 + 0.03 * math.sin(_tau * t));
    case ZaghlolMoment.thinking:
      return _Pose(rot: 0.05 * math.sin(_tau * t));
    case ZaghlolMoment.scanning:
      return _Pose(rot: 0.04 * math.sin(_tau * 2 * t));
    case ZaghlolMoment.counting:
      return _Pose(dy: 0.02 * s * math.sin(_tau * 2 * t));
    case ZaghlolMoment.payday:
      return _Pose(dy: -0.1 * s * math.sin(_tau * t).abs() * fade);
    case ZaghlolMoment.oops:
      return _Pose(rot: 0.12 * math.sin(_tau * 3 * t) * fade);
    case ZaghlolMoment.sleep:
      return _Pose(scale: 1 + 0.03 * math.sin(_tau * 2 * t) * fade);
    case ZaghlolMoment.pull:
      return _Pose(dy: -0.4 * s * (1 - Curves.easeOut.transform(t)));
    case ZaghlolMoment.tap:
      return _Pose(
        dy: -0.1 * s * arc,
        rot: _tau * Curves.easeInOut.transform(t),
      );
  }
}

List<Widget> _overlays(ZaghlolMoment m, double t, double s, ZColors c) {
  final icon = s * 0.2;
  Widget glyph(IconData d, Color color, {double opacity = 1, double? size}) =>
      Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Icon(d, size: size ?? icon, color: color),
      );
  Widget at(
    Widget w, {
    double? top,
    double? start,
    double? end,
    double? bottom,
  }) => PositionedDirectional(
    top: top,
    start: start,
    end: end,
    bottom: bottom,
    child: w,
  );

  List<Widget> burst(IconData d, Color color, int n) => [
    for (var i = 0; i < n; i++)
      Transform.translate(
        offset: Offset.fromDirection(
          _tau * i / n,
          s * 0.5 * Curves.easeOut.transform(t),
        ),
        child: glyph(d, color, opacity: 1 - t, size: icon * 0.7),
      ),
  ];

  List<Widget> fall(IconData d, Color color, int n, {bool loop = true}) => [
    for (var i = 0; i < n; i++)
      Builder(
        builder: (_) {
          final ph = loop ? (t + i / n) % 1 : t;
          final x = (i + 0.5) / n - 0.5;
          return Transform.translate(
            offset: Offset(x * s * 0.9, -s * 0.45 + ph * s * 0.9),
            child: glyph(
              d,
              color,
              opacity: math.sin(math.pi * ph) * 1.4,
              size: icon * 0.7,
            ),
          );
        },
      ),
  ];

  switch (m) {
    case ZaghlolMoment.shocked:
      return [
        at(
          glyph(
            Icons.priority_high_rounded,
            c.accentDark,
            opacity: math.sin(math.pi * t) * 2,
          ),
          top: 0,
          end: 0,
        ),
      ];
    case ZaghlolMoment.detective:
      return [
        at(
          glyph(Icons.search_rounded, c.primary, size: icon * 1.3),
          bottom: s * 0.05,
          end: 0,
        ),
      ];
    case ZaghlolMoment.listening:
      return [
        for (var i = 0; i < 2; i++)
          Builder(
            builder: (_) {
              final ph = (t + i / 2) % 1;
              return Opacity(
                opacity: (1 - ph) * 0.6,
                child: Container(
                  width: s * (0.6 + 0.5 * ph),
                  height: s * (0.6 + 0.5 * ph),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.primary, width: 2),
                  ),
                ),
              );
            },
          ),
      ];
    case ZaghlolMoment.thinking:
      return [
        at(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 3),
                  child: glyph(
                    Icons.circle,
                    c.textMuted,
                    opacity:
                        0.25 + 0.75 * math.max(0, math.sin(_tau * (t - i / 6))),
                    size: icon * 0.35,
                  ),
                ),
            ],
          ),
          top: 0,
          end: 0,
        ),
      ];
    case ZaghlolMoment.scanning:
      return [
        for (var i = 0; i < 3; i++)
          Builder(
            builder: (_) {
              final ph = (t + i / 3) % 1;
              return PositionedDirectional(
                top: s * (0.05 + 0.2 * i),
                end: s * (0.95 - 0.55 * ph) - icon,
                child: glyph(
                  Icons.mail_outline_rounded,
                  c.primary,
                  opacity: math.sin(math.pi * ph) * 1.5,
                  size: icon * 0.8,
                ),
              );
            },
          ),
      ];
    case ZaghlolMoment.counting:
      return fall(Icons.monetization_on_rounded, c.accent, 4);
    case ZaghlolMoment.saved:
      return burst(Icons.auto_awesome_rounded, c.accent, 6);
    case ZaghlolMoment.payday:
      return fall(Icons.monetization_on_rounded, c.accent, 6, loop: false);
    case ZaghlolMoment.oops:
      return [
        at(
          glyph(
            Icons.cloud_rounded,
            c.textMuted,
            opacity: math.sin(math.pi * t) * 1.5,
            size: icon * 1.3,
          ),
          top: 0,
          start: 0,
        ),
      ];
    case ZaghlolMoment.sleep:
      return [
        at(
          glyph(
            Icons.bedtime_rounded,
            c.textMuted,
            opacity: math.min(1, t * 3),
            size: icon * 1.1,
          ),
          top: s * 0.02,
          end: 0,
        ),
      ];
    case ZaghlolMoment.tap:
      return burst(Icons.auto_awesome_rounded, c.accent, 4);
    case ZaghlolMoment.tourGuide:
    case ZaghlolMoment.proud:
    case ZaghlolMoment.professor:
    case ZaghlolMoment.pull:
      return const [];
  }
}
