import 'package:flutter/material.dart';

import '../../features/mascot/presentation/zaghlol_avatar.dart';
import '../theme/z_tokens.dart';
import 'z_button.dart';

/// T-296: the shared empty state of every list screen. A sleeping Captain
/// Zaghlol (~120 px, decorative: the title beside it says it all), a short
/// line, an optional body and the screen's existing primary action.
class ZEmptyState extends StatelessWidget {
  const ZEmptyState({
    super.key,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.birdSize = 120,
  });

  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double birdSize;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZaghlolAvatar(moment: ZaghlolMoment.sleep, size: birdSize),
            const SizedBox(height: ZSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
            if (body != null) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: ZSpacing.lg),
              ZButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
