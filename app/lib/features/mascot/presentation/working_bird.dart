import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/z_haptics.dart';
import 'zaghlol_avatar.dart';

/// T-297 (D-87, bird place 4): the bird while the app works. Loops [moment]
/// only while [busy]; when work ends it settles to the idle pose; on [failed]
/// it plays `oops` (one-off, 1.4 s) with the oops haptic. Reduce motion is
/// handled by [ZaghlolAvatar] (still pose). Never intercepts taps.
class WorkingBird extends StatefulWidget {
  const WorkingBird({
    super.key,
    required this.busy,
    this.failed = false,
    this.moment = ZaghlolMoment.scanning,
    this.size = 48,
  });

  final bool busy;
  final bool failed;

  /// Loop moment while busy: scanning, counting or thinking.
  final ZaghlolMoment moment;
  final double size;

  /// Idle pose once the work is done.
  static const idleMoment = ZaghlolMoment.tourGuide;

  @override
  State<WorkingBird> createState() => _WorkingBirdState();
}

class _WorkingBirdState extends State<WorkingBird> {
  @override
  void initState() {
    super.initState();
    if (widget.failed) ZHaptics.play(ZHapticPattern.oops);
  }

  @override
  void didUpdateWidget(WorkingBird old) {
    super.didUpdateWidget(old);
    if (widget.failed && !old.failed) ZHaptics.play(ZHapticPattern.oops);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final moment = widget.failed
        ? ZaghlolMoment.oops
        : widget.busy
        ? widget.moment
        : WorkingBird.idleMoment;
    return ZaghlolAvatar(
      moment: moment,
      size: widget.size,
      semanticLabel: widget.failed
          ? l.workingBirdFailedA11y
          : l.workingBirdA11y,
    );
  }
}
