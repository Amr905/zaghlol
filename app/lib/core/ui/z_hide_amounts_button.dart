// D-67 / FR-HOME-06: the eye button that hides or shows every amount.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings/settings_keys.dart';
import '../settings/settings_providers.dart';
import '../theme/z_tokens.dart';
import 'z_haptics.dart';

/// Eye / eye-off toggle for `hide_amounts.app`. 48 dp target; the label says
/// what a tap does ("Hide amounts" while shown, "Show amounts" while hidden).
/// [color] tints the icon on a coloured card (the Home hero).
class ZHideAmountsButton extends ConsumerWidget {
  const ZHideAmountsButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hidden = ref.watch(hideAmountsProvider);
    final label = hidden ? l.commonAmountsShow : l.commonAmountsHide;
    return Semantics(
      label: label,
      button: true,
      child: IconButton(
        key: const Key('hide-amounts-toggle'),
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: color ?? ZColors.of(context).textMuted,
        ),
        onPressed: () async {
          ZHaptics.selection();
          final repo = await ref.read(settingsRepositoryProvider.future);
          await repo.set(Settings.hideAmountsApp, !hidden);
        },
      ),
    );
  }
}
