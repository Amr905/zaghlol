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
          child: ZCard(
            padding: EdgeInsetsDirectional.zero,
            child: SettingsRow(
              leading: Icon(Icons.workspace_premium, color: c.accent),
              title: plan == null
                  ? t.settingsMainGoldFree
                  : t.settingsMainGoldActive(plan),
              subtitle: plan == null ? t.settingsMainSeeGold : null,
              onTap: destinations.onGold,
            ),
          ),
        ),
        SettingsSection(
          title: t.settingsMainSectionGeneral,
          children: [
            SettingsRow(
              title: t.settingsMainPreferences,
              onTap: () => _push(context, const PreferencesScreen()),
            ),
            SettingsRow(
              key: const ValueKey('settings-account'),
              title: t.goldAccountTitle,
              onTap: destinations.onAccount,
            ),
            SettingsRow(
              title: t.settingsMainNotifications,
              onTap: destinations.onNotifications,
            ),
          ],
        ),
        SettingsSection(
          title: t.settingsMainSectionData,
          children: [
            SettingsRow(
              title: t.settingsMainCapture,
              subtitle: t.settingsMainCaptureSub(captureState),
              onTap: destinations.onCapture,
            ),
            SettingsRow(
              title: t.settingsMainCategories,
              onTap: destinations.onCategories,
            ),
            SettingsRow(
              title: t.settingsMainBackup,
              subtitle:
                  backupSubtitle ?? t.settingsMainBackupSub(_neverBackedUp, ''),
              onTap: destinations.onBackup,
            ),
            SettingsRow(
              title: t.settingsMainExports,
              onTap: destinations.onExports,
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsRow(
              title: t.settingsMainPrivacy,
              onTap: () => _push(context, const PrivacyScreen()),
            ),
            SettingsRow(
              title: t.settingsMainAbout,
              onTap: () => _push(context, const AboutScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
