// FU-224: fills Home's mascot slot (C-14) with Captain Zaghlol's message from
// [homeMascotMessageProvider]. The T-104 contextual cards stay below it, so
// the slot never hides a setup prompt. No message: the cards alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../features/home/application/home_mascot.dart';
import '../features/home/application/home_read_model.dart';
import '../features/home/presentation/cards/home_cards_view.dart';
import '../features/home/presentation/home_format.dart';
import '../features/home/presentation/home_screen.dart' show HomeActions;
import '../features/mascot/application/payday_celebration.dart';
import '../features/mascot/presentation/mascot_moments.dart';
import '../features/mascot/presentation/zaghlol_avatar.dart';

/// T-274: bigger than the 64 dp default; with the artboard's empty top
/// trimmed the bubble stays about as tall as before.
const _homeAvatarSize = 92.0;

class HomeMascotSlot extends ConsumerStatefulWidget {
  const HomeMascotSlot({super.key, required this.actions});

  final HomeActions actions;

  @override
  ConsumerState<HomeMascotSlot> createState() => _HomeMascotSlotState();
}

class _HomeMascotSlotState extends ConsumerState<HomeMascotSlot> {
  // T-215: set once when a payday celebration fires; the bubble keeps the
  // payday line for this visit (the mark is already stored, so a restart or
  // a rebuild never celebrates the same payday twice).
  bool _payday = false;

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    ref.listen(paydayCelebrationProvider, (_, next) {
      if (next.value != null && !_payday) setState(() => _payday = true);
    });
    if (!_payday && ref.read(paydayCelebrationProvider).value != null) {
      _payday = true;
    }
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
        if (_payday)
          ZaghlolTapBubble(
            key: const ValueKey('home-mascot-payday'),
            message: l.mascotPaydayLine,
            moment: ZaghlolMoment.payday,
          )
        else if (text != null)
          ZaghlolTapBubble(
            key: const ValueKey('home-mascot'),
            message: text,
            moment: ZaghlolMoment.proud,
            avatarSize: _homeAvatarSize,
            trimHeadroom: true,
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
