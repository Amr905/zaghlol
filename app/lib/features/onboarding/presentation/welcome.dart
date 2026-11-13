// T-055: S-01 Welcome & privacy. One primary action; the language toggle
// writes the language setting, so the whole app (and its direction) flips
// live through appLocaleProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({
    super.key,
    required this.onStart,
    required this.onRestore,
    this.onPrivacy,
  });

  /// "Let's go" -> S-02 / S-03.
  final VoidCallback onStart;

  /// "I already use Zaghlol" -> backup restore flow (T-153).
  final VoidCallback onRestore;

  /// "Privacy details" -> S-71; the link is hidden while null.
  final VoidCallback? onPrivacy;

  Future<void> _toggleLanguage(WidgetRef ref, bool isArabic) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(
      Settings.language,
      isArabic ? LanguagePref.en : LanguagePref.ar,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final points = [
      (Icons.lock_outline, l.onboardingWelcomePointOnPhone),
      (Icons.account_balance_outlined, l.onboardingWelcomePointNoPassword),
      (Icons.block, l.onboardingWelcomePointNoAds),
    ];
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Semantics(
                      button: true,
                      label: l.onboardingWelcomeLanguageToggleA11y,
                      excludeSemantics: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: ZSpacing.minTarget,
                          minWidth: ZSpacing.minTarget,
                        ),
                        child: TextButton(
                          key: const ValueKey('welcome-language-toggle'),
                          onPressed: () => _toggleLanguage(ref, isArabic),
                          child: Text(
                            l.onboardingWelcomeLanguageToggle,
                            style: ZType.label.copyWith(color: c.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ZSpacing.lg),
                  const Center(
                    child: ZaghlolAvatar(
                      moment: ZaghlolMoment.tourGuide,
                      size: 160,
                    ),
                  ),
                  const SizedBox(height: ZSpacing.xl),
                  Text(
                    l.onboardingWelcomeTitle,
                    style: ZType.headline.copyWith(color: c.text),
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  Text(
                    l.onboardingWelcomeSubtitle,
                    style: ZType.body.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: ZSpacing.xl),
                  for (final (icon, text) in points)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: ZSpacing.md,
                      ),
                      child: Row(
                        children: [
                          ExcludeSemantics(
                            child: Icon(icon, size: 20, color: c.primary),
                          ),
                          const SizedBox(width: ZSpacing.md),
                          Expanded(
                            child: Text(
                              text,
                              style: ZType.bodySmall.copyWith(color: c.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: ZSpacing.xl),
                  ZButton(
                    key: const ValueKey('welcome-start'),
                    label: l.onboardingWelcomeStart,
                    onPressed: onStart,
                    expand: true,
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  ZButton(
                    key: const ValueKey('welcome-restore'),
                    label: l.onboardingWelcomeRestore,
                    onPressed: onRestore,
                    variant: ZButtonVariant.text,
                    expand: true,
                  ),
                  if (onPrivacy != null)
                    ZButton(
                      key: const ValueKey('welcome-privacy'),
                      label: l.onboardingWelcomePrivacyLink,
                      onPressed: onPrivacy,
                      variant: ZButtonVariant.text,
                      expand: true,
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
