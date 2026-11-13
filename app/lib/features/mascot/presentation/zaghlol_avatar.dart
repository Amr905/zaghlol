import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce =
        ref.watch(reduceMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    final artboard = ref.watch(zaghlolArtboardProvider);

    final Widget body = (artboard != null && !reduce)
        ? artboard(context, moment, talk, size)
        : Image.asset(
            stillAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          );

    return IgnorePointer(
      child: Semantics(
        image: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox.square(
          key: const ValueKey('zaghlol-avatar'),
          dimension: size,
          child: ExcludeSemantics(child: body),
        ),
      ),
    );
  }
}
