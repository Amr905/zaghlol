import 'package:flutter/material.dart';

import '../../features/mascot/presentation/zaghlol_avatar.dart';
import '../theme/z_tokens.dart';

/// Captain Zaghlol's speech card (mockups 03 / 25): apricot cream card, the bird at
/// the start, text after it. The bird ignores pointers.
class ZMascotBubble extends StatelessWidget {
  const ZMascotBubble({
    super.key,
    required this.message,
    this.moment = ZaghlolMoment.proud,
    this.avatarSize = 64,
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
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.md,
                vertical: ZSpacing.sm,
              ),
              child: Row(
                children: [
                  ZaghlolAvatar(moment: moment, size: avatarSize),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Text(
                      message,
                      style: ZType.bodySmall.copyWith(
                        color: c.text,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
