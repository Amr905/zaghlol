// T-066 (EC-14): the Home / Settings banner shown on iOS when no Shortcut or
// Apple Pay capture arrived for 7+ days. The action opens the Capture screen;
// the dismiss button snoozes it for 7 days.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../application/ios_nudge_providers.dart';

class IosSetupNudge extends ConsumerWidget {
  const IosSetupNudge({super.key, this.onCheck, this.padding});

  /// Opens the Capture screen (S-61).
  final VoidCallback? onCheck;

  /// Space around the banner; it takes none when the nudge is hidden.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(iosNudgeDaysProvider);
    if (days == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final n = ref.watch(digitsModeProvider(lang)).render('$days');
    final banner = ZBanner(
      key: const ValueKey('ios-setup-nudge'),
      message: l.iosSetupNudgeSilent(days, n),
      tone: ZBannerTone.warning,
      actionLabel: onCheck == null ? null : l.iosSetupNudgeCheck,
      onAction: onCheck,
      onDismiss: () => snoozeIosNudge(ref),
      dismissSemanticsLabel: l.iosSetupNudgeSnoozeA11y,
    );
    return Padding(
      padding: padding ?? const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: banner,
    );
  }
}
