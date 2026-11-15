// T-024: the modal Add route (S-30 Quick add). Only the sheet frame and the
// four entry points; their destinations (S-31, S-13, S-32, S-44) arrive with
// their own tasks through [AddSheet.onSelected].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/gold/application/gating.dart';
import '../../../features/voice/application/voice_providers.dart';
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
    showDragHandle: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    sheetAnimationStyle: const AnimationStyle(
      duration: ZMotion.sheet,
      curve: ZMotion.curve,
    ),
    builder: (_) => child,
  );
}

/// T-082: the Asset entry carries the Gold badge for Free users (assets are
/// a Gold feature, FR-WLT); the wiring sends them to the paywall.
class AddSheet extends ConsumerWidget {
  const AddSheet({super.key, this.onSelected, this.voiceLeft});

  /// Called with the chosen entry point; the default just closes the sheet.
  final ValueChanged<AddAction>? onSelected;

  /// Free-tier voice quota (remaining, max) shown under the grid; null reads
  /// it from [voiceLeftProvider] (T-120; Gold and unknown hide the line).
  final (int, int)? voiceLeft;

  void _select(BuildContext context, AddAction action) {
    if (onSelected != null) {
      onSelected!(action);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    final voiceLeft = this.voiceLeft ?? ref.watch(voiceLeftProvider).value;
    final options = <(AddAction, IconData, String, String, String, bool)>[
      (
        AddAction.say,
        Icons.mic_none_rounded,
        l10n.homeQuickAddSay,
        l10n.homeQuickAddSayHint,
        l10n.homeQuickAddSayA11y,
        false,
      ),
      (
        AddAction.type,
        Icons.keyboard_outlined,
        l10n.homeQuickAddType,
        l10n.homeQuickAddTypeHint,
        l10n.homeQuickAddTypeA11y,
        false,
      ),
      (
        AddAction.scan,
        Icons.photo_camera_outlined,
        l10n.homeQuickAddScan,
        l10n.homeQuickAddScanHint,
        l10n.homeQuickAddScanA11y,
        false,
      ),
      (
        AddAction.asset,
        Icons.account_balance_outlined,
        l10n.homeQuickAddAsset,
        l10n.homeQuickAddAssetHint,
        '${l10n.homeQuickAddAssetA11y}${gold ? '' : ', ${l10n.commonGoldBadge}'}',
        !gold,
      ),
    ];
    Widget cell(int i) {
      final (action, icon, label, hint, a11y, badge) = options[i];
      return Expanded(
        child: _AddOption(
          icon: icon,
          label: label,
          hint: hint,
          semanticLabel: a11y,
          goldBadge: badge ? l10n.commonGoldBadge : null,
          onTap: () => _select(context, action),
        ),
      );
    }

    final lang = Localizations.localeOf(context).languageCode;
    String digits(int n) => lang == 'ar'
        ? n.toString().replaceAllMapped(
            RegExp('[0-9]'),
            (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)),
          )
        : '$n';
    return ZSheetBody(
      title: l10n.homeQuickAddTitle,
      centerTitle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(0),
                const SizedBox(width: ZSpacing.md),
                cell(1),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cell(2),
                const SizedBox(width: ZSpacing.md),
                cell(3),
              ],
            ),
          ),
          if (voiceLeft != null) ...[
            const SizedBox(height: ZSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.mic_none_rounded,
                    size: 18,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(width: ZSpacing.xs),
                Flexible(
                  child: Text(
                    l10n.homeQuickAddVoiceLeft(
                      digits(voiceLeft.$1),
                      digits(voiceLeft.$2),
                    ),
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: ZSpacing.xl),
        ],
      ),
    );
  }
}

class _AddOption extends StatelessWidget {
  const _AddOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.semanticLabel,
    required this.onTap,
    this.goldBadge,
  });

  final IconData icon;
  final String label;
  final String hint;
  final String semanticLabel;
  final VoidCallback onTap;
  final String? goldBadge;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.card);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.outline),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primaryContainer,
                      ),
                      child: Icon(icon, color: c.primary),
                    ),
                    const Spacer(),
                    if (goldBadge != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.warningBg,
                          borderRadius: BorderRadius.circular(ZRadius.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: ZSpacing.md,
                            vertical: ZSpacing.xs,
                          ),
                          child: Text(
                            goldBadge!,
                            style: ZType.caption.copyWith(color: c.warningText),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: ZSpacing.md),
                Text(
                  label,
                  style: ZType.title.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(hint, style: ZType.bodySmall.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
