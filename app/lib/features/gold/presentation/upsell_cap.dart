// T-146: max one unsolicited upgrade prompt per week (A-22, FR-GOLD-05).
// Prompts the user asks for (tapping a locked item, "See Gold") are never
// capped; only hints the app shows by itself go through [tryShow].

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/gating.dart';
import 'gold_ui_ports.dart';

const Duration upsellInterval = Duration(days: 7);

final class UpsellCap {
  UpsellCap(this._store, this._now);
  final UpsellCapStore _store;
  final DateTime Function() _now;

  /// True, and records the prompt, when none was shown in the last week.
  /// Gold users never see one.
  Future<bool> tryShow({required bool isGold}) {
    if (isGold) return Future.value(false);
    // Serialised: a second caller waits for the first check-and-mark.
    final run = _tail.then((_) => _check());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _tail = Future<void>.value();

  Future<bool> _check() async {
    final now = _now();
    final last = await _store.lastShown();
    if (last != null && now.difference(last) < upsellInterval) return false;
    await _store.markShown(now);
    return true;
  }
}

final upsellCapProvider = Provider<UpsellCap>(
  (ref) => UpsellCap(
    ref.watch(upsellCapStoreProvider),
    ref.watch(upsellClockProvider),
  ),
  name: 'upsellCapProvider',
);

/// First caller of the cap (FU-166a): a prompt the app raises by itself. Opens
/// the paywall at most once a week and never for Gold users; false when it
/// did not. Never throws (a failed settings read means no prompt).
final unsolicitedPaywallProvider =
    Provider<Future<bool> Function(GoldCapability capability)>(
      (ref) => (capability) async {
        try {
          final allowed = await ref
              .read(upsellCapProvider)
              .tryShow(isGold: ref.read(entitlementStateProvider).isGold);
          if (!allowed) return false;
          ref.read(paywallTriggerProvider)(capability);
          return true;
        } on Object {
          return false;
        }
      },
      name: 'unsolicitedPaywallProvider',
    );
