import 'package:flutter/services.dart';

/// Strength of a haptic tick.
enum ZHaptic { none, selection, light, medium }

/// The one place haptic feedback is fired, so it is easy to tune or turn off.
/// [HapticFeedback] is a no-op on platforms without a haptic engine.
abstract final class ZHaptics {
  /// Set to false to silence every tick (e.g. from a future setting).
  static bool enabled = true;

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
