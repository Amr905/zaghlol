// FU-224: fills Home's mascot slot (C-14) with Captain Zaghlol's message from
// [homeMascotMessageProvider]. The T-104 contextual cards stay below it, so
// the slot never hides a setup prompt. No message: the cards alone.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/routing/app_routes.dart';
import '../core/settings/settings_providers.dart';
import 'app_navigation.dart' show openImportFlow;
import '../features/home/application/home_mascot.dart';
import '../features/home/application/home_read_model.dart';
import '../features/home/presentation/cards/home_cards_view.dart';
import '../features/home/presentation/home_format.dart';
import '../features/home/presentation/home_screen.dart' show HomeActions;
import '../features/mascot/application/mascot_tips.dart';
import '../features/mascot/application/payday_celebration.dart';
import '../features/mascot/presentation/mascot_moments.dart';
import '../features/mascot/presentation/payday_sheet.dart';
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
  // T-294: a pending celebration waits until Home is the visible screen on
  // the Home tab; the mark is stored only once the sheet is opened.
  PaydayCelebration? _pending;
  bool _scheduled = false;

  void _celebrate(PaydayCelebration? salary) {
    if (salary == null ||
        ref.read(paydayShownThisSessionProvider).contains(salary.txnId)) {
      return;
    }
    _pending = salary;
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Route popped back to Home, or the Home tab became active.
    if (_pending != null) _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final salary = _pending;
      if (!mounted || salary == null) return;
      // Only over Home on the Home tab, never over another screen or sheet;
      // otherwise stay pending (didChangeDependencies retries).
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      final shown = ref.read(paydayShownThisSessionProvider);
      _pending = null;
      if (!shown.add(salary.txnId)) return;
      unawaited(
        ref
            .read(settingsRepositoryProvider.future)
            .then((r) => markPaydayCelebrated(r, salary.txnId))
            .catchError((_) {}),
      );
      unawaited(
        showPaydaySheet(context, salary, openBudget: widget.actions.openBudget),
      );
    });
  }

  void _open(MascotTipTarget target) {
    final a = widget.actions;
    switch (target) {
      case MascotTipTarget.none:
        break;
      case MascotTipTarget.add:
        context.push(AppRoutes.add);
      case MascotTipTarget.review:
        context.push(AppRoutes.review);
      case MascotTipTarget.transactions:
        context.push(AppRoutes.transactions);
      case MascotTipTarget.insights:
        context.go(AppRoutes.insights);
      case MascotTipTarget.ask:
        context.go(AppRoutes.zaghlol);
      case MascotTipTarget.budget:
        a.openBudget?.call();
      case MascotTipTarget.settings:
        a.openSettings?.call();
      case MascotTipTarget.importStatement:
        openImportFlow(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    ref.listen(paydayCelebrationProvider, (_, next) => _celebrate(next.value));
    _celebrate(ref.read(paydayCelebrationProvider).value);
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
    // T-277: a tip only fills an empty slot; the proud/alert lines win.
    final tip = text != null ? null : ref.watch(homeTipProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tip != null) ...[
          ZaghlolTapBubble(
            key: const ValueKey('home-mascot-tip'),
            message: tip.text(l),
            moment: switch (tip.group) {
              MascotTipGroup.usage => ZaghlolMoment.tourGuide,
              MascotTipGroup.smart => ZaghlolMoment.professor,
              MascotTipGroup.habit => ZaghlolMoment.proud,
            },
          ),
          if (tip.target != MascotTipTarget.none)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('home-mascot-tip-open'),
                onPressed: () => _open(tip.target),
                child: Text(l.mascotTipShowMe),
              ),
            ),
        ] else if (text != null)
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
