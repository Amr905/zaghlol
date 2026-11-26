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
    this.replay = 0,
    this.size = 96,
    this.semanticLabel,
    this.trimHeadroom = false,
  });

  final ZaghlolMoment moment;
  final bool talk;
  final double size;

  /// T-276: bump to play the same [moment] again on the same widget (never
  /// change the key for that: it reloads the artboard).
  final int replay;

  /// Localised description from the caller (AppLocalizations). Null makes the
  /// bird decorative, e.g. when the bubble beside it already says everything.
  final String? semanticLabel;

  /// T-274: the Rive artboard keeps the top quarter free for props (hat,
  /// magnifier, falling coins); the bird itself spans 26% to 99% of the height
  /// (measured on the rendered file). With [trimHeadroom] the avatar box is only
  /// [riveBirdHeightFactor] as tall and the empty top is clipped, so a card can
  /// show a bigger bird without empty space above its head. Only applies to the
  /// Rive artboard; the still and the interim art have no such margin.
  final bool trimHeadroom;

  static const riveBirdHeightFactor = 0.76;

  static const stillAsset = 'assets/mascot/zaghlol_still.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce =
        ref.watch(reduceMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    final artboard = ref.watch(zaghlolArtboardProvider);

    // Reduce motion: still pose only. Otherwise an explicit artboard override
    // wins, then the illustrator's Rive file when bundled (T-088), else the
    // interim Flutter animation of the brand still (T-099).
    final hasRive = ref.watch(zaghlolRivePresentProvider).value ?? false;
    final Widget body = reduce
        ? Image.asset(
            stillAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          )
        : artboard != null
        ? artboard(context, moment, talk, size)
        : hasRive
        ? RiveMascot(
            moment: moment,
            talk: talk,
            replay: replay,
            size: size,
            loader: ref.read(riveMascotLoaderProvider),
          )
        : InterimMascot(moment: moment, talk: talk, replay: replay, size: size);

    final trim = trimHeadroom && !reduce && artboard == null && hasRive;
    final height = trim ? size * riveBirdHeightFactor : size;
    return IgnorePointer(
      child: Semantics(
        image: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: SizedBox(
          key: const ValueKey('zaghlol-avatar'),
          width: size,
          height: height,
          child: ExcludeSemantics(
            child: trim
                ? ClipRect(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.bottomCenter,
                      minHeight: size,
                      maxHeight: size,
                      child: body,
                    ),
                  )
                : body,
          ),
        ),
      ),
    );
  }
}
