// T-146: max one unsolicited upgrade prompt per week (A-22, FR-GOLD-05).
// Prompts the user asks for (tapping a locked item, "See Gold") are never
// capped; only hints the app shows by itself go through [tryShow].

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gold_ui_ports.dart';

const Duration upsellInterval = Duration(days: 7);

final class UpsellCap {
  UpsellCap(this._store, this._now);
  final UpsellCapStore _store;
  final DateTime Function() _now;

  /// True, and records the prompt, when none was shown in the last week.
  /// Gold users never see one.
  Future<bool> tryShow({required bool isGold}) async {
    if (isGold) return false;
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
