import 'package:flutter/material.dart';

import '../../features/mascot/presentation/zaghlol_avatar.dart';
import '../theme/z_tokens.dart';

/// Captain Zaghlol's speech card (mockups 03 / 25): apricot cream card, text at
/// the start, the bird at the end. The bird ignores pointers.
class ZMascotBubble extends StatelessWidget {
  const ZMascotBubble({
    super.key,
    required this.message,
    this.moment = ZaghlolMoment.proud,
    this.avatarSize = 68,
    this.onTap,
  });

  final String message;
  final ZaghlolMoment moment;
  final double avatarSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.card);
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.zaghlolBg,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.xl,
                ZSpacing.md,
                ZSpacing.md,
                ZSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: ZType.body.copyWith(color: c.text, height: 1.6),
                    ),
                  ),
                  const SizedBox(width: ZSpacing.sm),
                  ZaghlolAvatar(moment: moment, size: avatarSize),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
