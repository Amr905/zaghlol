// T-024: the modal Add route (S-30 Quick add). Only the sheet frame and the
// four entry points; their destinations (S-31, S-13, S-32, S-44) arrive with
// their own tasks through [AddSheet.onSelected].

import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/z_tokens.dart';
import '../z_sheet.dart';

enum AddAction { say, type, scan, asset }

/// A go_router page that shows its child as a modal bottom sheet (drag
/// handle, back and swipe-down close it, the tab underneath stays put).
class ModalSheetPage<T> extends Page<T> {
  const ModalSheetPage({super.key, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    sheetAnimationStyle: const AnimationStyle(
      duration: ZMotion.sheet,
      curve: ZMotion.curve,
    ),
    builder: (_) => child,
  );
}

class AddSheet extends StatelessWidget {
  const AddSheet({super.key, this.onSelected});

  /// Called with the chosen entry point; the default just closes the sheet.
  final ValueChanged<AddAction>? onSelected;

  void _select(BuildContext context, AddAction action) {
    if (onSelected != null) {
      onSelected!(action);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <(AddAction, IconData, String, String)>[
      (
        AddAction.say,
        Icons.mic_rounded,
        l10n.homeQuickAddSay,
        l10n.homeQuickAddSayA11y,
      ),
      (
        AddAction.type,
        Icons.keyboard_rounded,
        l10n.homeQuickAddType,
        l10n.homeQuickAddTypeA11y,
      ),
      (
        AddAction.scan,
        Icons.photo_camera_rounded,
        l10n.homeQuickAddScan,
        l10n.homeQuickAddScanA11y,
      ),
      (
        AddAction.asset,
        Icons.savings_rounded,
        l10n.homeQuickAddAsset,
        l10n.homeQuickAddAssetA11y,
      ),
    ];
    return ZSheetBody(
      title: l10n.homeQuickAddTitle,
      child: Wrap(
        spacing: ZSpacing.sm,
        runSpacing: ZSpacing.sm,
        children: [
          for (final (action, icon, label, a11y) in options)
            _AddOption(
              icon: icon,
              label: label,
              semanticLabel: a11y,
              onTap: () => _select(context, action),
            ),
        ],
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(ZRadius.lg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 72,
              minHeight: ZSpacing.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.md,
                vertical: ZSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: c.onPrimaryContainer),
                  const SizedBox(height: ZSpacing.xs),
                  Text(
                    label,
                    style: ZType.label.copyWith(color: c.onPrimaryContainer),
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
