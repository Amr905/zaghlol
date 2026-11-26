// T-277: Captain Zaghlol's tips (how to use the app, what the smart features
// do, light money habits). Pure catalog plus rotation; the Home slot shows
// one when no alert-type or celebration line is up. Counters only are
// stored, nothing personal. Nothing here logs.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../../home/application/home_cards.dart' show setupInstalledOnProvider;

enum MascotTipGroup { usage, smart, habit }

/// Where a how-to tip's "Show me" goes. `none`: the tip is just text.
enum MascotTipTarget {
  none,
  add,
  review,
  transactions,
  insights,
  ask,
  budget,
  settings,
  importStatement,
}

class MascotTip {
  MascotTip(this.group, this.target, this.text, {this.androidOnly = false});

  final MascotTipGroup group;
  final MascotTipTarget target;
  final String Function(AppLocalizations l) text;

  /// Shown only on Android (the feature does not exist on iOS).
  final bool androidOnly;
}

/// First two weeks after install: usage tips lead (PO 2026-11-26).
const int kTipNewcomerDays = 14;

/// Every tip, in the order each group cycles through them.
final List<MascotTip> mascotTips = [
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.add,
    (l) => l.mascotTipUseScan,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.none,
    (l) => l.mascotTipUseShare,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.add,
    (l) => l.mascotTipUseSay,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.none,
    (l) => l.mascotTipUseLinkCard,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.settings,
    (l) => l.mascotTipUsePayday,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.importStatement,
    (l) => l.mascotTipUseStatement,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.review,
    (l) => l.mascotTipUseReview,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.transactions,
    (l) => l.mascotTipUseSearchPerson,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.none,
    (l) => l.mascotTipUseHide,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.budget,
    (l) => l.mascotTipUseBudget,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.none,
    (l) => l.mascotTipUseSalary,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.ask,
    (l) => l.mascotTipUseAsk,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.none,
    (l) => l.mascotTipUseDue,
  ),
  MascotTip(
    MascotTipGroup.usage,
    MascotTipTarget.insights,
    (l) => l.mascotTipUseInsights,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.ask,
    (l) => l.mascotTipSmartAsk,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.add,
    (l) => l.mascotTipSmartVoice,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartSms,
    androidOnly: true,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartCategory,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartDue,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartPayday,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartDuplicate,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.add,
    (l) => l.mascotTipSmartReceipt,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartInstapay,
  ),
  MascotTip(
    MascotTipGroup.smart,
    MascotTipTarget.none,
    (l) => l.mascotTipSmartTransfer,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitCoffee,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitPigeon,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitCheck,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitSale,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitSmall,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitWait,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitTreat,
  ),
  MascotTip(
    MascotTipGroup.habit,
    MascotTipTarget.none,
    (l) => l.mascotTipHabitSubs,
  ),
];

List<MascotTip> tipsOf(MascotTipGroup g, {bool android = true}) => [
  for (final t in mascotTips)
    if (t.group == g && (android || !t.androidOnly)) t,
];

/// Counters: the next index to show in each group, and tips shown so far.
class TipRotation {
  const TipRotation({
    this.usage = 0,
    this.smart = 0,
    this.habit = 0,
    this.shown = 0,
  });

  final int usage;
  final int smart;
  final int habit;
  final int shown;

  static const start = TipRotation();

  int of(MascotTipGroup g) => switch (g) {
    MascotTipGroup.usage => usage,
    MascotTipGroup.smart => smart,
    MascotTipGroup.habit => habit,
  };

  TipRotation advanced(MascotTipGroup g) => TipRotation(
    usage: g == MascotTipGroup.usage ? usage + 1 : usage,
    smart: g == MascotTipGroup.smart ? smart + 1 : smart,
    habit: g == MascotTipGroup.habit ? habit + 1 : habit,
    shown: shown + 1,
  );

  String encode() => '$usage.$smart.$habit.$shown';

  static TipRotation decode(String s) {
    final p = s.split('.');
    if (p.length != 4) return start;
    final n = [for (final x in p) int.tryParse(x)];
    if (n.any((x) => x == null || x < 0 || x > 999999)) return start;
    return TipRotation(usage: n[0]!, smart: n[1]!, habit: n[2]!, shown: n[3]!);
  }
}

const _newcomerOrder = [
  MascotTipGroup.usage,
  MascotTipGroup.usage,
  MascotTipGroup.smart,
  MascotTipGroup.usage,
  MascotTipGroup.usage,
  MascotTipGroup.habit,
];
const _steadyOrder = [
  MascotTipGroup.usage,
  MascotTipGroup.smart,
  MascotTipGroup.habit,
];

/// The next tip and the rotation after it. A tip in a group comes back only
/// after every other tip of that group was shown.
({MascotTip tip, TipRotation next}) pickTip({
  required TipRotation rotation,
  required int daysSinceInstall,
  bool android = true,
}) {
  final order = daysSinceInstall < kTipNewcomerDays
      ? _newcomerOrder
      : _steadyOrder;
  final group = order[rotation.shown % order.length];
  final list = tipsOf(group, android: android);
  return (
    tip: list[rotation.of(group) % list.length],
    next: rotation.advanced(group),
  );
}

/// The tip for this app session: picks once, stores the advanced counters.
final homeTipProvider = FutureProvider<MascotTip?>((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  final installed = await ref.watch(setupInstalledOnProvider.future);
  final today = ref.read(todayProvider);
  final rotation = TipRotation.decode(await repo.get(Settings.mascotTipState));
  final pick = pickTip(
    rotation: rotation,
    daysSinceInstall: today.difference(installed),
    android: defaultTargetPlatform == TargetPlatform.android,
  );
  await repo.set(Settings.mascotTipState, pick.next.encode());
  return pick.tip;
}, name: 'homeTipProvider');
