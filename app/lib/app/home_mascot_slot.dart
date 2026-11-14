// FU-224: fills Home's mascot slot (C-14) with Captain Zaghlol's message from
// [homeMascotMessageProvider]. The T-104 contextual cards stay below it, so
// the slot never hides a setup prompt. No message: the cards alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/ui/z_mascot_bubble.dart';
import '../features/home/application/home_mascot.dart';
import '../features/home/application/home_read_model.dart';
import '../features/home/presentation/cards/home_cards_view.dart';
import '../features/home/presentation/home_format.dart';
import '../features/home/presentation/home_screen.dart' show HomeActions;
import '../features/mascot/presentation/zaghlol_avatar.dart';

class HomeMascotSlot extends ConsumerWidget {
  const HomeMascotSlot({super.key, required this.actions});

  final HomeActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final format = HomeFormat.of(context, ref);
    final message = ref.watch(homeMascotMessageProvider).value;
    final hasTransactions =
        ref.watch(homeModelProvider).value?.recent.isNotEmpty ?? false;
    final text = switch (message) {
      MascotSavedMore(:final amount) => l.homeMascotProudSavedMore(
        format.money(amount),
      ),
      MascotOnTrack() => l.homeMascotProudOnTrack,
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text != null)
          ZMascotBubble(
            key: const ValueKey('home-mascot'),
            message: text,
            moment: ZaghlolMoment.proud,
          ),
        HomeContextualCards(
          hasTransactions: hasTransactions,
          openSetBudget: actions.openSetBudget,
          openBackup: actions.openBackup,
          openFinishSetup: actions.openFinishSetup,
        ),
      ],
    );
  }
}
