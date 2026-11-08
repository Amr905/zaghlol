import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

enum ZButtonVariant { primary, gold, secondary, text, destructive }

enum ZButtonSize {
  /// 48 dp high.
  medium(48),

  /// 40 dp visual height (inside cards); the tap target stays 48 dp.
  small(40);

  const ZButtonSize(this.height);
  final double height;
}

/// C-03 Button. States: default, pressed (ink well), disabled (38% opacity),
/// loading (spinner replaces the label, width kept).
class ZButton extends StatelessWidget {
  const ZButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ZButtonVariant.primary,
    this.size = ZButtonSize.medium,
    this.loading = false,
    this.icon,
    this.expand = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final ZButtonVariant variant;
  final ZButtonSize size;
  final bool loading;
  final IconData? icon;

  /// Fill the available width.
  final bool expand;

  /// Overrides the spoken label (already localised by the caller).
  final String? semanticsLabel;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final (
      Color fg,
      Color? fill,
      Gradient? gradient,
      BorderSide? border,
    ) = switch (variant) {
      ZButtonVariant.primary => (c.onPrimary, c.primary, null, null),
      ZButtonVariant.gold => (
        c.onAccent,
        null,
        LinearGradient(colors: [c.accentLight, c.accentDark]),
        null,
      ),
      ZButtonVariant.secondary => (c.primary, c.primaryContainer, null, null),
      ZButtonVariant.text => (c.primary, null, null, null),
      ZButtonVariant.destructive => (c.dangerBg, c.dangerText, null, null),
    };
    final shape = BorderRadius.circular(ZRadius.pill);
    final textStyle = ZType.label.copyWith(
      color: fg,
      fontWeight: FontWeight.w600,
    );

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: ZSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            style: textStyle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final body = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: loading ? 0 : 1, child: content),
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          ),
      ],
    );

    final button = Opacity(
      opacity: onPressed == null && !loading ? 0.38 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            gradient: gradient,
            borderRadius: shape,
            border: border == null ? null : Border.fromBorderSide(border),
          ),
          child: InkWell(
            borderRadius: shape,
            onTap: _enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: ZSpacing.xl,
                  vertical: ZSpacing.sm,
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: _enabled ? onPressed : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Align(
          alignment: AlignmentDirectional.center,
          widthFactor: expand ? null : 1,
          heightFactor: 1,
          child: button,
        ),
      ),
    );
  }
}
