// T-162: the grouped C-16 list pieces shared by the Settings screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';

/// Renders digits in the user's digits mode for the language shown.
String localDigits(WidgetRef ref, BuildContext context, String text) {
  final lang = Localizations.localeOf(context).languageCode;
  return ref.watch(digitsModeProvider(lang)).render(text);
}

class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.screen,
            vertical: ZSpacing.lg,
          ),
          children: [
            if (Navigator.of(context).canPop())
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Material(
                  color: c.surface,
                  shape: const CircleBorder(),
                  elevation: 1,
                  shadowColor: c.shadow,
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    constraints: const BoxConstraints(
                      minWidth: ZSpacing.minTarget,
                      minHeight: ZSpacing.minTarget,
                    ),
                    icon: const BackButtonIcon(),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            const SizedBox(height: ZSpacing.md),
            Semantics(
              header: true,
              child: Text(title, style: ZType.display.copyWith(color: c.text)),
            ),
            const SizedBox(height: ZSpacing.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: ZSpacing.xs,
                bottom: ZSpacing.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: ZType.label.copyWith(color: c.textMuted),
                ),
              ),
            ),
          ZCard(
            padding: EdgeInsetsDirectional.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.card),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: c.outline,
                        indent: ZSpacing.lg,
                        endIndent: ZSpacing.lg,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable row: title, optional subtitle and trailing chevron (mirrors in
/// RTL through [Icons.chevron_right] with a directional flip).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.leading,
    this.icon,
    this.tint,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  /// Rounded colour tile with an icon (mockup 16); a [tint] of null uses the
  /// primary colour.
  final IconData? icon;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.lg,
            vertical: ZSpacing.md,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint ?? c.primary,
                    borderRadius: BorderRadius.circular(ZRadius.lg),
                  ),
                  child: Icon(icon, color: c.surface),
                ),
                const SizedBox(width: ZSpacing.md),
              ] else if (leading != null) ...[
                leading!,
                const SizedBox(width: ZSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ZType.body.copyWith(color: c.text)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: ZType.bodySmall.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (onTap != null && trailing == null)
                Icon(Icons.chevron_right, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return MergeSemantics(
      child: SwitchListTile(
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
        ),
        title: Text(title, style: ZType.body.copyWith(color: c.text)),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// A labelled control row (label above the control, so 1.3x text fits).
class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ZType.label.copyWith(color: c.textMuted)),
          const SizedBox(height: ZSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Shows an error as a snackbar.
void showSettingsMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
