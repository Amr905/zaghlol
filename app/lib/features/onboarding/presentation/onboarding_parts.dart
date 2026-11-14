// Shared pieces of the onboarding screens (mockups 01, 19, 23, 24, 02, 26,
// 27): segmented progress + skip bar, mascot, check dot, mint note, and the
// pinned-bottom page layout.

import 'package:flutter/material.dart';

import '../../../core/theme/z_tokens.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';

/// Top bar: progress segments at the start, "Skip" at the end.
class OnbTopBar extends StatelessWidget {
  const OnbTopBar({
    super.key,
    required this.step,
    required this.total,
    required this.stepLabel,
    this.skipLabel,
    this.onSkip,
    this.skipKey = const ValueKey('setup-skip'),
  });

  final int step;
  final int total;

  /// Localised "Step x of y", spoken for the segments.
  final String stepLabel;
  final String? skipLabel;
  final VoidCallback? onSkip;
  final Key skipKey;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.screen,
        ZSpacing.sm,
        ZSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Semantics(
            label: stepLabel,
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Container(
                      key: ValueKey('onb-segment-$i'),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i < step ? c.primary : c.primaryContainer,
                        borderRadius: BorderRadius.circular(ZRadius.pill),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          if (onSkip != null && skipLabel != null)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ZSpacing.minTarget,
                minWidth: ZSpacing.minTarget,
              ),
              child: TextButton(
                key: skipKey,
                onPressed: onSkip,
                child: Text(
                  skipLabel!,
                  style: ZType.titleSmall.copyWith(color: c.primary),
                ),
              ),
            )
          else
            const SizedBox(height: ZSpacing.minTarget),
        ],
      ),
    );
  }
}

/// Captain Zaghlol, decorative, centred.
class OnbMascot extends StatelessWidget {
  const OnbMascot({
    super.key,
    this.moment = ZaghlolMoment.tourGuide,
    this.size = 180,
  });

  final ZaghlolMoment moment;
  final double size;

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: ZaghlolAvatar(moment: moment, size: size),
    ),
  );
}

/// Filled green dot with a white check.
class OnbCheckDot extends StatelessWidget {
  const OnbCheckDot({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
        child: Icon(Icons.check, size: size * 0.6, color: c.onPrimary),
      ),
    );
  }
}

/// Round tinted tile holding an icon (welcome points, list leading icons).
class OnbIconTile extends StatelessWidget {
  const OnbIconTile({
    super.key,
    required this.icon,
    this.size = 40,
    this.background,
    this.foreground,
    this.radius,
  });

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  /// Null = circle.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? c.primaryContainer,
          shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius == null ? null : BorderRadius.circular(radius!),
        ),
        child: Icon(icon, size: size * 0.5, color: foreground ?? c.primary),
      ),
    );
  }
}

/// Mint-container note with a leading glyph (lock) and text.
class OnbMintNote extends StatelessWidget {
  const OnbMintNote({
    super.key,
    required this.text,
    this.icon = Icons.lock_outline,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: c.primary)),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Text(
              text,
              style: ZType.bodySmall.copyWith(color: c.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolling content with the actions pinned to the bottom (stays pinned when
/// the content is short, scrolls together when text is large).
class OnbPage extends StatelessWidget {
  const OnbPage({super.key, required this.content, required this.actions});

  final List<Widget> content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.screen,
          vertical: ZSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 16),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...content,
                const SizedBox(height: ZSpacing.xl),
                const Spacer(),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
