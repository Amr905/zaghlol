// T-099: event -> mascot moment wiring that screens share. Strings come from
// the copy deck (ARB mascot*). Nothing here logs or touches data.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/z_mascot_bubble.dart';
import 'zaghlol_avatar.dart';
import 'zaghlol_mascot.dart';

/// The copy-deck tap lines, in rotation order (`mascotTapLine1`..`10`).
List<String> mascotTapLines(AppLocalizations l) => [
  l.mascotTapLine1,
  l.mascotTapLine2,
  l.mascotTapLine3,
  l.mascotTapLine4,
  l.mascotTapLine5,
  l.mascotTapLine6,
  l.mascotTapLine7,
  l.mascotTapLine8,
  l.mascotTapLine9,
  l.mascotTapLine10,
];

/// The next unused tap line; wraps after the last (copy deck 1.2).
String mascotTapLine(AppLocalizations l, int tapIndex) {
  final lines = mascotTapLines(l);
  return lines[tapIndex % lines.length];
}

/// "Saved" confirmation line; [seed] picks one of the three at random.
String mascotSavedLine(AppLocalizations l, int seed) => switch (seed % 3) {
  0 => l.mascotSavedLine1,
  1 => l.mascotSavedLine2,
  _ => l.mascotSavedLine3,
};

/// A mascot bubble with the tap easter egg (D-35): each tap plays the `tap`
/// hop and shows the next copy-deck line for 0.8 s of motion, then the bubble
/// goes back to [message] with [moment]. The whole card is the 48 dp+ target.
class ZaghlolTapBubble extends StatefulWidget {
  const ZaghlolTapBubble({
    super.key,
    required this.message,
    this.moment = ZaghlolMoment.proud,
  });

  final String message;
  final ZaghlolMoment moment;

  @override
  State<ZaghlolTapBubble> createState() => _ZaghlolTapBubbleState();
}

class _ZaghlolTapBubbleState extends State<ZaghlolTapBubble> {
  int _taps = 0;
  String? _line;
  Timer? _back;

  void _tap() {
    final l = AppLocalizations.of(context);
    _back?.cancel();
    setState(() {
      _line = mascotTapLine(l, _taps);
      _taps++;
    });
    _back = Timer(ZaghlolMoment.tap.duration, () {
      if (mounted) setState(() => _back = null);
    });
  }

  @override
  void dispose() {
    _back?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZMascotBubble(
      message: _line ?? widget.message,
      moment: _back != null ? ZaghlolMoment.tap : widget.moment,
      avatarKey: ValueKey('tap-$_taps'),
      onTap: _tap,
    );
  }
}

/// Pull-to-refresh with the `pull` moment: Captain Zaghlol drops in from the
/// top while [onRefresh] runs and leaves when it ends (loops only during real
/// work). Never intercepts touches.
class MascotRefresh extends StatefulWidget {
  const MascotRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<MascotRefresh> createState() => _MascotRefreshState();
}

class _MascotRefreshState extends State<MascotRefresh> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        RefreshIndicator(onRefresh: _run, child: widget.child),
        if (_busy)
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: Center(
              child: ZaghlolAvatar(
                key: const ValueKey('mascot-pull'),
                moment: ZaghlolMoment.pull,
                size: 56,
                semanticLabel: l.mascotPullRefreshingA11y,
              ),
            ),
          ),
      ],
    );
  }
}
