// T-162: S-60 Settings, the entry point to every setting (FR-ONB-07). Every
// preference is within 2 taps: this list, then the screen (or its control).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../capture/presentation/ios_setup_nudge.dart';
import 'about_screen.dart';
import 'preferences_screen.dart';
import 'privacy_screen.dart';
import 'settings_ports.dart';
import 'settings_widgets.dart';

/// Where the rows owned by other tasks go (T-174 wires the router). A null
/// callback hides nothing: the row still shows but does not navigate.
class SettingsDestinations {
  const SettingsDestinations({
    this.onGold,
    this.onFinishSetup,
    this.onNotifications,
    this.onCapture,
    this.onCategories,
    this.onBackup,
    this.onExports,
    this.onAccount,
  });

  final VoidCallback? onGold;
  final VoidCallback? onFinishSetup;
  final VoidCallback? onNotifications;
  final VoidCallback? onCapture;
  final VoidCallback? onCategories;
  final VoidCallback? onBackup;
  final VoidCallback? onExports;

  /// S-69 Gold & account (FR-GLD sign-in, restore, manage).
  final VoidCallback? onAccount;
}

// The select key of settingsMainBackupSub for no backup.
const _neverBackedUp = 'never';

class SettingsMainScreen extends ConsumerWidget {
  const SettingsMainScreen({
    super.key,
    this.destinations = const SettingsDestinations(),
    this.backupSubtitle,
  });

  final SettingsDestinations destinations;

  /// Already-formatted "Last: 30 Oct" line from the backup feature; null
  /// shows "No backup yet".
  final String? backupSubtitle;

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final stepsLeft = ref.watch(setupStepsLeftProvider);
    final plan = ref.watch(goldPlanProvider);
    final captureState = ref.watch(captureStateProvider);
    return SettingsScaffold(
      title: t.settingsMainTitle,
      children: [
        IosSetupNudge(
          onCheck: destinations.onCapture,
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.lg),
        ),
        if (stepsLeft > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.lg),
            child: ZCard(
              padding: EdgeInsetsDirectional.zero,
              child: SettingsRow(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: c.warningText,
                ),
                title: t.settingsMainFinishSetup(
                  stepsLeft,
                  localDigits(ref, context, '$stepsLeft'),
                ),
                onTap: destinations.onFinishSetup,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
          child: Material(
            borderRadius: BorderRadius.circular(ZRadius.hero),
            clipBehavior: Clip.antiAlias,
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ZRadius.hero),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerEnd,
                  end: AlignmentDirectional.centerStart,
                  colors: [c.zaghlolBg, c.accentLight.withValues(alpha: 0.5)],
                ),
              ),
              child: InkWell(
                onTap: destinations.onGold,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 88),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.star_outline_rounded,
                            color: c.onAccent,
                          ),
                        ),
                        const SizedBox(width: ZSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan == null
                                    ? t.settingsMainGoldFree
                                    : t.settingsMainGoldActive(plan),
                                style: ZType.title.copyWith(color: c.onAccent),
                              ),
                              if (plan == null)
                                Text(
                                  t.settingsMainSeeGold,
                                  style: ZType.bodySmall.copyWith(
                                    color: c.warningText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: c.warningText),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SettingsSection(
          title: t.settingsMainSectionGeneral,
          children: [
            SettingsRow(
              icon: Icons.palette_outlined,
              tint: const Color(0xFF9585CF),
              title: t.settingsMainPreferences,
              onTap: () => _push(context, const PreferencesScreen()),
            ),
            SettingsRow(
              key: const ValueKey('settings-account'),
              icon: Icons.person_outline_rounded,
              tint: c.accentDark,
              title: t.goldAccountTitle,
              onTap: destinations.onAccount,
            ),
            SettingsRow(
              icon: Icons.notifications_none_rounded,
              tint: c.dangerText,
              title: t.settingsMainNotifications,
              onTap: destinations.onNotifications,
            ),
          ],
        ),
        SettingsSection(
          title: t.settingsMainSectionData,
          children: [
            SettingsRow(
              icon: Icons.chat_bubble_outline_rounded,
              tint: c.primary,
              title: t.settingsMainCapture,
              subtitle: t.settingsMainCaptureSub(captureState),
              onTap: destinations.onCapture,
            ),
            SettingsRow(
              icon: Icons.sell_outlined,
              tint: c.accentDark,
              title: t.settingsMainCategories,
              onTap: destinations.onCategories,
            ),
            SettingsRow(
              icon: Icons.cloud_outlined,
              tint: const Color(0xFF6A8FD8),
              title: t.settingsMainBackup,
              subtitle:
                  backupSubtitle ?? t.settingsMainBackupSub(_neverBackedUp, ''),
              onTap: destinations.onBackup,
            ),
            SettingsRow(
              icon: Icons.description_outlined,
              tint: c.primary,
              title: t.settingsMainExports,
              onTap: destinations.onExports,
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsRow(
              icon: Icons.shield_outlined,
              tint: c.primary,
              title: t.settingsMainPrivacy,
              onTap: () => _push(context, const PrivacyScreen()),
            ),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              tint: c.textMuted,
              title: t.settingsMainAbout,
              onTap: () => _push(context, const AboutScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
