// T-104 (FR-ONB-11): the Settings "Finish setup" row. Shown only while a
// skipped onboarding step is left. The Settings screen drops it at the top.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/ui/z_card.dart';
import '../application/setup_steps.dart';

class FinishSetupRow extends ConsumerWidget {
  const FinishSetupRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = stepsLeft(ref.watch(setupProgressProvider).value ?? const {});
    if (left.isEmpty) return const SizedBox.shrink();
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final l = AppLocalizations.of(context);
    return ZListRow(
      key: const ValueKey('settings-finish-setup'),
      leading: const Icon(Icons.warning_amber_rounded),
      title: l.settingsMainFinishSetup(
        left.length,
        digits.render('${left.length}'),
      ),
      onTap: onTap,
    );
  }
}
