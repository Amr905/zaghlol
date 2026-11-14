import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

/// Surface card: separation by tone plus a very soft shadow, no outline
/// (05-theme-2026 section 4). Radius 24.
class ZCard extends StatelessWidget {
  const ZCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(ZSpacing.lg),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Override, e.g. `zaghlolBg` for Captain Zaghlol's bubbles.
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.card);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
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
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    // A tappable card reads as one labelled button (its text), not as an
    // unlabelled tap node beside separate text nodes (NFR-UX-02).
    return onTap == null ? card : MergeSemantics(child: card);
  }
}

/// C-16 / C-05 list row: leading, title, subtitle, trailing. Minimum height
/// 56 dp (72 with a subtitle).
class ZListRow extends StatelessWidget {
  const ZListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.showChevron = false,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Disclosure chevron, mirrored automatically in RTL.
  final bool showChevron;

  /// Hairline under the row, inset on the leading side past the tile
  /// (mockup 03 lists).
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 56 : 72),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.sm,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: ZSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: ZType.titleSmall.copyWith(color: c.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: ZType.bodySmall.copyWith(color: c.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: ZSpacing.md),
              trailing!,
            ],
            if (showChevron) ...[
              const SizedBox(width: ZSpacing.xs),
              Icon(Icons.chevron_right, color: c.textMuted),
            ],
          ],
        ),
      ),
    );
    final inkRow = InkWell(onTap: enabled ? onTap : null, child: row);
    return Semantics(
      container: true,
      button: onTap != null,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: showDivider
            ? DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    inkRow,
                    PositionedDirectional(
                      start: leading == null
                          ? ZSpacing.lg
                          : ZSpacing.lg + 40 + ZSpacing.md,
                      end: 0,
                      bottom: 0,
                      child: Divider(height: 1, thickness: 1, color: c.outline),
                    ),
                  ],
                ),
              )
            : inkRow,
      ),
    );
  }
}

/// Category tile: 40 dp circle, category colour at 14% opacity, with the
/// category glyph (emoji or icon) as [child]. Decorative: the category name is
/// always shown as text next to it.
class ZCategoryTile extends StatelessWidget {
  const ZCategoryTile({
    super.key,
    required this.color,
    required this.child,
    this.size = 40,
  });

  final Color color;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: AlignmentDirectional.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.14),
        ),
        child: child,
      ),
    );
  }
}

/// Hero card (mockups 03 / 20 / 21): mint gradient, radius 28, soft shadow.
/// The gradient runs from the top end to the bottom start, so it mirrors in
/// RTL.
class ZHeroCard extends StatelessWidget {
  const ZHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(ZSpacing.xl),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.hero);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [c.heroFrom, c.heroTo],
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return card;
  }
}

/// Rounded gradient progress bar (hero card). [value] is 0..1, fills from the
/// start edge. Decorative: the figures beside it carry the meaning.
class ZProgressBar extends StatelessWidget {
  const ZProgressBar({super.key, required this.value, this.height = 12});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final r = BorderRadius.circular(ZRadius.pill);
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.18),
          borderRadius: r,
        ),
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [c.progressFrom, c.progressTo],
              ),
            ),
            child: SizedBox(height: height),
          ),
        ),
      ),
    );
  }
}
