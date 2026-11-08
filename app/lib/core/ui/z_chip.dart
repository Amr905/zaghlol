import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

/// Borderless pill chip (C-06 / C-08): selected = primaryContainer.
class ZChip extends StatelessWidget {
  const ZChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.onClear,
    this.clearSemanticsLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Shows a trailing clear (x) affordance (C-08 active filter).
  final VoidCallback? onClear;
  final String? clearSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final fg = selected ? c.onPrimaryContainer : c.text;
    final fill = selected ? c.primaryContainer : c.surfaceAlt;
    final shape = BorderRadius.circular(ZRadius.pill);
    final chip = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(color: fill, borderRadius: shape),
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.lg,
                vertical: ZSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: ZSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: ZType.label.copyWith(color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onClear != null)
                    Semantics(
                      button: true,
                      label: clearSemanticsLabel,
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: onClear,
                        radius: 24,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: ZSpacing.sm,
                          ),
                          child: Icon(Icons.close, size: 18, color: fg),
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
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: onClear == null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: chip,
        ),
      ),
    );
  }
}

enum ZPillTone { neutral, info, success, warning, danger, gold }

/// C-21 Badge / status pill: small caption text with optional icon.
class ZPill extends StatelessWidget {
  const ZPill({
    super.key,
    required this.label,
    this.tone = ZPillTone.neutral,
    this.icon,
  });

  final String label;
  final ZPillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final (Color fg, Color bg) = switch (tone) {
      ZPillTone.neutral => (c.textMuted, c.surfaceAlt),
      ZPillTone.info => (c.onPrimaryContainer, c.primaryContainer),
      ZPillTone.success => (c.incomeText, c.incomeBg),
      ZPillTone.warning => (c.warningText, c.warningBg),
      ZPillTone.danger => (c.dangerText, c.dangerBg),
      ZPillTone.gold => (c.onAccent, c.accent),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ZRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.sm,
            vertical: ZSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: ZSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  style: ZType.caption.copyWith(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
