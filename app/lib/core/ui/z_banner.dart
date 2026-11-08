import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';
import 'z_button.dart';

enum ZBannerTone { info, warning, error, success }

/// C-20 Banner: icon, message and optional action. Persistent until resolved
/// unless [onDismiss] is given.
class ZBanner extends StatelessWidget {
  const ZBanner({
    super.key,
    required this.message,
    this.tone = ZBannerTone.info,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.dismissSemanticsLabel,
  });

  final String message;
  final ZBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final String? dismissSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final (Color fg, Color bg, IconData icon) = switch (tone) {
      ZBannerTone.info => (
        c.onPrimaryContainer,
        c.primaryContainer,
        Icons.info_outline,
      ),
      ZBannerTone.warning => (
        c.warningText,
        c.warningBg,
        Icons.warning_amber_rounded,
      ),
      ZBannerTone.error => (
        c.dangerText,
        c.dangerBg,
        Icons.error_outline,
      ),
      ZBannerTone.success => (
        c.incomeText,
        c.incomeBg,
        Icons.check_circle_outline,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: tone == ZBannerTone.error,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ZRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, color: fg)),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: ZSpacing.xs,
                      ),
                      child: Text(
                        message,
                        style: ZType.bodySmall.copyWith(color: fg),
                      ),
                    ),
                    if (actionLabel != null)
                      ZButton(
                        label: actionLabel!,
                        onPressed: onAction,
                        variant: ZButtonVariant.text,
                        size: ZButtonSize.small,
                      ),
                  ],
                ),
              ),
              if (onDismiss != null)
                Semantics(
                  button: true,
                  label: dismissSemanticsLabel,
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: onDismiss,
                    child: SizedBox(
                      width: ZSpacing.minTarget,
                      height: ZSpacing.minTarget,
                      child: Icon(Icons.close, color: fg),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
