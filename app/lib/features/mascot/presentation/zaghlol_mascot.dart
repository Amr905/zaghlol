// T-099: the mascot widget interface. Screens never talk to an
// implementation: ZaghlolAvatar picks one. [InterimMascot] animates the
// approved brand still with Flutter animations (works today); [RiveMascot]
// plays `assets/rive/zaghlol.riv` once T-088 delivers it. Contract for the
// illustrator: docs/02-design/mascot-rive-handoff.md.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'zaghlol_avatar.dart' show ZaghlolMoment;

/// Where the illustrator's file lands (T-088).
const kZaghlolRivAsset = 'assets/rive/zaghlol.riv';

/// One mascot rendering of a [moment] at [size]. Implementations animate by
/// themselves, replay when [moment] changes (or the widget key changes), and
/// never take pointer input.
abstract class ZaghlolMascot extends StatefulWidget {
  const ZaghlolMascot({
    super.key,
    required this.moment,
    required this.talk,
    required this.size,
  });

  final ZaghlolMoment moment;
  final bool talk;
  final double size;
}

/// Looping moments run only while real work runs (08-mascot-motion rules);
/// everything else is a one-off of at most 3 s and then rests on the still.
extension ZaghlolMomentTiming on ZaghlolMoment {
  bool get loops => switch (this) {
    ZaghlolMoment.listening ||
    ZaghlolMoment.thinking ||
    ZaghlolMoment.scanning ||
    ZaghlolMoment.counting => true,
    _ => false,
  };

  /// One cycle (loops) or the whole one-off, from the 08 motion table.
  Duration get duration => switch (this) {
    ZaghlolMoment.tourGuide => const Duration(milliseconds: 1600),
    ZaghlolMoment.proud => const Duration(milliseconds: 900),
    ZaghlolMoment.shocked => const Duration(milliseconds: 1100),
    ZaghlolMoment.detective => const Duration(milliseconds: 2000),
    ZaghlolMoment.professor => const Duration(milliseconds: 1400),
    ZaghlolMoment.listening => const Duration(milliseconds: 1400),
    ZaghlolMoment.thinking => const Duration(milliseconds: 1500),
    ZaghlolMoment.scanning => const Duration(milliseconds: 1600),
    ZaghlolMoment.counting => const Duration(milliseconds: 1400),
    ZaghlolMoment.saved => const Duration(milliseconds: 900),
    ZaghlolMoment.payday => const Duration(milliseconds: 1600),
    ZaghlolMoment.oops => const Duration(milliseconds: 1400),
    ZaghlolMoment.sleep => const Duration(milliseconds: 2800),
    ZaghlolMoment.pull => const Duration(milliseconds: 600),
    ZaghlolMoment.tap => const Duration(milliseconds: 800),
  };
}

/// Whether the illustrator's `.riv` is bundled. Overridable in tests.
final zaghlolRivePresentProvider = FutureProvider<bool>((ref) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().contains(kZaghlolRivAsset);
  } catch (_) {
    return false;
  }
}, name: 'zaghlolRivePresentProvider');
