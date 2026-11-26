import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_card.dart';
import '../../../mascot/presentation/zaghlol_avatar.dart';

/// T-296: header of the review list while items wait: a detective Zaghlol,
/// "{n} messages need a look" and one helper line.
class ReviewHeader extends StatelessWidget {
  const ReviewHeader({super.key, required this.count, required this.countText});

  final int count;

  /// [count] rendered with the user's digit style.
  final String countText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      child: Row(
        children: [
          const ZaghlolAvatar(moment: ZaghlolMoment.detective, size: 64),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.ingestionReviewHeaderTitle(count, countText),
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.xs),
                Text(
                  l.ingestionReviewHeaderHelper,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
