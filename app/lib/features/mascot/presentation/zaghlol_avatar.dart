import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'interim_mascot.dart';
import 'rive_mascot.dart';
import 'zaghlol_mascot.dart';

/// The 15 mascot moments (08-mascot-motion section 1, copy-deck Rive states).
/// Names match the `ZaghlolAvatar` Rive state machine inputs.
enum ZaghlolMoment {
  tourGuide,
  proud,
  shocked,
  detective,
  professor,
  listening,
  thinking,
  scanning,
  counting,
  saved,
  payday,
  oops,
  sleep,
  pull,
  tap,
}

/// In-app "reduce motion" toggle (FR-MAS-03). The settings screen overrides
/// or writes this; the OS setting is read separately from [MediaQuery].
class ReduceMotionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // Riverpod 3 notifiers expose state directly; a setter keeps call sites tidy.
  void set(bool value) => state = value;
}

final reduceMotionProvider = NotifierProvider<ReduceMotionNotifier, bool>(
  ReduceMotionNotifier.new,
);

/// Builds the animated artboard (Rive, T-088). Receives the moment, whether
/// the bird is speaking, and the square size.
typedef ZaghlolArtboardBuilder = Widget Function(
  BuildContext context,
  ZaghlolMoment moment,
  bool talk,
  double size,
);

/// Seam for the Rive runtime. Stays null until `zaghlol.riv` ships; T-088
/// overrides it with a builder, with no change to [ZaghlolAvatar]'s API.
final zaghlolArtboardProvider = Provider<ZaghlolArtboardBuilder?>(
  (ref) => null,
);

/// Captain Zaghlol. One instance per screen; never blocks taps (it ignores
/// pointers). Shows the still pose when reduce motion is on (OS or app) or
/// when no artboard is registered.
class ZaghlolAvatar extends ConsumerWidget {
  const ZaghlolAvatar({
    super.key,
    this.moment = ZaghlolMoment.tourGuide,
    this.talk = false,
    this.size = 96,
    this.semanticLabel,
  });

  final ZaghlolMoment moment;
  final bool talk;
  final double size;

  /// Localised description from the caller (AppLocalizations). Null makes the
  /// bird decorative, e.g. when the bubble beside it already says everything.
  final String? semanticLabel;

  static const stillAsset = 'assets/mascot/zaghlol_still.png';

  /// T-268: the shipped still has zero transparent margin (its left thumb-up
  /// hand outline touches pixel column 0) and the Rive widget clips to its box,
  /// so any rotate/scale or ancestor clip nibbled the hand. The art is painted
  /// inside this inset on every side (symmetric, so RTL needs no branching).
  static const paintInsetFraction = 0.06;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce =
        ref.watch(reduceMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    final artboard = ref.watch(zaghlolArtboardProvider);

    // Reduce motion: still pose only. Otherwise an explicit artboard override
    // wins, then the illustrator's Rive file when bundled (T-088), else the
    // interim Flutter animation of the brand still (T-099).
    final inner = size * (1 - 2 * paintInsetFraction);
    final hasRive = ref.watch(zaghlolRivePresentProvider).value ?? false;
    final Widget body = reduce
        ? Image.asset(
            stillAsset,
            width: inner,
            height: inner,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          )
        : artboard != null
        ? artboard(context, moment, talk, inner)
        : hasRive
        ? RiveMascot(moment: moment, talk: talk, size: inner)
        : InterimMascot(moment: moment, talk: talk, size: inner);

    return IgnorePointer(
      child: Semantics(
        image: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox.square(
          key: const ValueKey('zaghlol-avatar'),
          dimension: size,
          child: Center(child: ExcludeSemantics(child: body)),
        ),
      ),
    );
  }
}
