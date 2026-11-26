import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

/// Strength of a haptic tick.
enum ZHaptic { none, selection, light, medium }

/// Animation-synced haptic patterns (T-293, D-87). The beat table is in
/// `docs/02-design/08-mascot-motion-and-bank-logos.md` (Haptics) and in
/// `T-293.md`; [ZHaptics.timelineMs] reads the same table.
enum ZHapticPattern { payday, saved, oops, birdTap }

/// How hard one hit of a pattern is. Native maps it to TICK / CLICK / THUD
/// (Android) or sharpness (iOS); the Dart fallback maps it to
/// light / medium / heavy impact.
enum ZHapticStrength { tick, click, thud }

/// One beat of a pattern: when it fires and how strong it is.
class ZHapticHit {
  const ZHapticHit(this.atMs, this.strength, this.intensityPct);
  final int atMs;
  final ZHapticStrength strength;

  /// 1..100.
  final int intensityPct;
}

/// The one place haptic feedback is fired, so it is easy to tune or turn off.
/// [HapticFeedback] is a no-op on platforms without a haptic engine.
abstract final class ZHaptics {
  /// Set to false to silence every tick (e.g. from a future setting).
  static bool enabled = true;

  /// App-level "reduce motion" (FR-MAS-03). The OS setting is read too.
  static bool reduceMotion = false;

  /// Native pattern player (T-293). Plain channel: it carries beats only.
  static const MethodChannel channel = MethodChannel('app.zaghlol/haptics');

  static const Map<ZHapticPattern, List<ZHapticHit>> _table = {
    ZHapticPattern.payday: [
      ZHapticHit(0, ZHapticStrength.tick, 40),
      ZHapticHit(140, ZHapticStrength.tick, 50),
      ZHapticHit(260, ZHapticStrength.tick, 60),
      ZHapticHit(360, ZHapticStrength.tick, 75),
      ZHapticHit(450, ZHapticStrength.tick, 90),
      ZHapticHit(700, ZHapticStrength.thud, 100),
      ZHapticHit(1300, ZHapticStrength.tick, 40),
      ZHapticHit(1420, ZHapticStrength.tick, 30),
    ],
    ZHapticPattern.saved: [
      ZHapticHit(0, ZHapticStrength.click, 80),
      ZHapticHit(90, ZHapticStrength.click, 100),
    ],
    ZHapticPattern.oops: [
      ZHapticHit(0, ZHapticStrength.thud, 60),
      ZHapticHit(140, ZHapticStrength.thud, 60),
    ],
    ZHapticPattern.birdTap: [ZHapticHit(0, ZHapticStrength.tick, 60)],
  };

  /// The beats of [p].
  static List<ZHapticHit> hits(ZHapticPattern p) => _table[p]!;

  /// Hit offsets in ms, for syncing animation beats.
  static List<int> timelineMs(ZHapticPattern p) => [
    for (final h in _table[p]!) h.atMs,
  ];

  /// Plays [p]. No-op when haptics are off. With reduce motion (app toggle,
  /// the [reduceMotion] argument or the OS setting) only one light tick fires.
  /// Never throws: a missing or failing native side falls back to Flutter's
  /// [HapticFeedback] on a timer.
  static Future<void> play(ZHapticPattern p, {bool? reduceMotion}) async {
    if (!enabled) return;
    final reduce =
        reduceMotion ??
        (ZHaptics.reduceMotion ||
            PlatformDispatcher
                .instance
                .accessibilityFeatures
                .disableAnimations);
    if (reduce) {
      fire(ZHaptic.light);
      return;
    }
    final beats = _table[p]!;
    var played = false;
    try {
      played =
          await channel.invokeMethod<bool>('play', {
            'hits': [
              for (final h in beats) [h.atMs, h.strength.index, h.intensityPct],
            ],
          }) ??
          false;
    } on MissingPluginException {
      played = false;
    } on PlatformException {
      played = false;
    }
    if (!played) await _fallback(beats);
  }

  static Future<void> _fallback(List<ZHapticHit> beats) async {
    var last = 0;
    for (final h in beats) {
      if (!enabled) return;
      final wait = h.atMs - last;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      last = h.atMs;
      switch (h.strength) {
        case ZHapticStrength.tick:
          unawaited(HapticFeedback.lightImpact());
        case ZHapticStrength.click:
          unawaited(HapticFeedback.mediumImpact());
        case ZHapticStrength.thud:
          unawaited(HapticFeedback.heavyImpact());
      }
    }
  }

  /// Tab switches, toggles, chips.
  static void selection() => fire(ZHaptic.selection);

  /// Plain taps: tiles, secondary buttons, undo, swipe-to-delete.
  static void light() => fire(ZHaptic.light);

  /// Add button, save and confirm.
  static void medium() => fire(ZHaptic.medium);

  static void fire(ZHaptic kind) {
    if (!enabled) return;
    switch (kind) {
      case ZHaptic.none:
        break;
      case ZHaptic.selection:
        HapticFeedback.selectionClick();
      case ZHaptic.light:
        HapticFeedback.lightImpact();
      case ZHaptic.medium:
        HapticFeedback.mediumImpact();
    }
  }

  /// Wraps [onChanged] for a Switch so a flip ticks once.
  static ValueChanged<bool>? onToggle(ValueChanged<bool>? onChanged) =>
      onChanged == null
      ? null
      : (v) {
          selection();
          onChanged(v);
        };
}
