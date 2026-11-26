// T-099 / T-088: plays assets/rive/zaghlol.riv. Names are the contract in
// docs/02-design/mascot-rive-handoff.md. If the file fails to load, shows the
// still so the app never breaks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' as rive;

import 'zaghlol_avatar.dart'
    show ZaghlolAvatar, ZaghlolMoment, reduceMotionProvider;
import 'zaghlol_mascot.dart';

const kRiveArtboard = 'Zaghlol';
const kRiveStateMachine = 'ZaghlolAvatar';
const kRiveInputState = 'state'; // number: ZaghlolMoment.index
const kRiveInputTalk = 'talk'; // boolean
const kRiveInputReduceMotion =
    'reduceMotion'; // boolean (we only mount when off)

/// FU-287: the decoded file is loaded once per app run and shared by every
/// mount (never disposed; the controllers are per mount). A failure is not
/// cached, so a later mount may try again.
Future<rive.File>? _sharedFile;

Future<rive.File> _loadSharedFile() => _sharedFile ??= () async {
  try {
    // rive 0.14 needs the native runtime started once before any file
    // loads (idempotent). If it can't start, the caller shows the still.
    if (!await rive.RiveNative.init()) throw StateError('native');
    final file = await rive.File.asset(
      kZaghlolRivAsset,
      riveFactory: rive.Factory.rive,
    );
    if (file == null) throw StateError('decode');
    return file;
  } catch (_) {
    _sharedFile = null;
    rethrow;
  }
}();

/// FU-287: what the Rive mascots did, so an on-device test can tell "playing"
/// from "fell back to the still". Counters only; nothing is logged.
abstract final class RiveMascotProbe {
  /// Controllers created (the file decoded and the state machine found).
  static int loaded = 0;

  /// Loads that threw (native runtime, decode, artboard or state machine).
  static int failedToLoad = 0;

  /// Paint-time exceptions that sent a mascot back to the still.
  static int paintFailed = 0;

  /// T-232: names the state machine reports as its layers change state (the
  /// animation names, `mood03_detective`, `fx09_saved`, `talkOn`...). The
  /// device test checks that every state value reaches its animation.
  static final List<String> stateNames = <String>[];

  /// Off in the app: only the on-device test turns state recording on, so
  /// the looping layers never grow a list in production.
  static bool recordStates = false;

  /// Upper bound on [stateNames] even when recording.
  static const int maxStateNames = 500;

  @visibleForTesting
  static void recordState(String name) {
    if (stateNames.length >= maxStateNames) stateNames.removeAt(0);
    stateNames.add(name);
  }

  static void reset() {
    recordStates = false;
    loaded = 0;
    failedToLoad = 0;
    paintFailed = 0;
    stateNames.clear();
  }
}

/// Test hook: forgets the shared file.
void resetSharedRiveFileForTest() => _sharedFile = null;

/// Paints [child]; if painting throws, calls [onError] once and paints
/// nothing, so the mascot can fall back to the still (FU-287).
class _PaintGuard extends SingleChildRenderObjectWidget {
  const _PaintGuard({required this.onError, required super.child});
  final VoidCallback onError;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintGuard(onError);

  @override
  void updateRenderObject(BuildContext context, _RenderPaintGuard r) =>
      r.onError = onError;
}

class _RenderPaintGuard extends RenderProxyBox {
  _RenderPaintGuard(this.onError);
  VoidCallback onError;
  bool _failed = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_failed) return;
    try {
      super.paint(context, offset);
    } catch (_) {
      _failed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => onError());
    }
  }
}

/// T-276: one live artboard + state machine. Behind an interface so widget
/// tests (where rive_native cannot load) can drive the mascot with a fake.
abstract class RiveMascotHandle {
  /// The widget that paints the artboard. Must stay the same object for the
  /// life of the handle so the render object is never recreated.
  Widget get widget;

  /// Sets the moment and the talk flag through state machine inputs. With
  /// [replay] the same moment plays again from its start.
  void apply(ZaghlolMoment moment, bool talk, {bool replay = false});

  /// Releases the controller (the shared file stays).
  void dispose();
}

typedef RiveMascotLoader = Future<RiveMascotHandle> Function();

/// The real loader: shared decoded file, one controller per mascot.
Future<RiveMascotHandle> loadRiveMascotHandle() async {
  final file = await _loadSharedFile();
  final controller = rive.RiveWidgetController(
    file,
    artboardSelector: rive.ArtboardSelector.byName(kRiveArtboard),
    stateMachineSelector: rive.StateMachineSelector.byName(kRiveStateMachine),
  );
  return _RealRiveHandle(controller);
}

/// Overridable in tests.
final riveMascotLoaderProvider = Provider<RiveMascotLoader>(
  (ref) => loadRiveMascotHandle,
  name: 'riveMascotLoaderProvider',
);

/// T-276: called once at start-up so the first mascot never waits for the
/// native runtime, the file decode or the asset manifest. Failures are
/// swallowed; the mascot then shows the still as before.
Future<void> preloadRiveMascot({
  bool? animationsDisabled,
  Future<void> Function()? load,
}) async {
  // FU-374: reduce motion never mounts Rive, so it never loads it either.
  final off =
      animationsDisabled ??
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
  if (off) return;
  if (load != null) {
    await load();
    return;
  }
  try {
    await AssetManifest.loadFromAssetBundle(rootBundle);
    await _loadSharedFile();
  } catch (_) {
    // The mascot falls back to the still when it mounts.
  }
}

/// FU-391: starts [preloadRiveMascot] after the first frame, when the platform
/// accessibility flags are set and the in-app reduce-motion setting is known.
/// Either one off means no load. Wraps the app root; shows [child] unchanged.
class RivePreloadOnFirstFrame extends ConsumerStatefulWidget {
  const RivePreloadOnFirstFrame({super.key, required this.child, this.load});

  final Widget child;

  /// Test seam: replaces the real load.
  @visibleForTesting
  final Future<void> Function()? load;

  @override
  ConsumerState<RivePreloadOnFirstFrame> createState() =>
      _RivePreloadOnFirstFrameState();
}

class _RivePreloadOnFirstFrameState
    extends ConsumerState<RivePreloadOnFirstFrame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(reduceMotionProvider)) return;
      unawaited(
        preloadRiveMascot(
          animationsDisabled: MediaQuery.maybeDisableAnimationsOf(context),
          load: widget.load,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// Legacy state machine inputs: stable and enough for one number + two flags.
// ignore_for_file: deprecated_member_use, invalid_use_of_internal_member
class _RealRiveHandle implements RiveMascotHandle {
  _RealRiveHandle(this._controller) {
    if (RiveMascotProbe.recordStates) {
      _stateHandle = _controller.stateMachine.onStateChanged(
        RiveMascotProbe.recordState,
      );
    }
    widget = rive.RiveWidget(controller: _controller, fit: rive.Fit.contain);
  }

  final rive.RiveWidgetController _controller;
  rive.CallbackHandler? _stateHandle;
  bool _disposed = false;

  /// Bumped on every apply: a pending replay of an older tap gives up (the
  /// last tap wins, nothing queues).
  int _generation = 0;

  @override
  late final Widget widget;

  @override
  void apply(ZaghlolMoment moment, bool talk, {bool replay = false}) {
    if (_disposed) return;
    final gen = ++_generation;
    final sm = _controller.stateMachine;
    sm.boolean(kRiveInputTalk)?.value = talk;
    sm.boolean(kRiveInputReduceMotion)?.value = false;
    final input = sm.number(kRiveInputState);
    if (input == null) return;
    final target = moment.index.toDouble();
    if (replay && input.value == target) {
      // Setting the same value does not replay: leave it for one frame, then
      // come back. The machine starts every one-off from its rest pose, so
      // this shows no other animation.
      input.value = ((moment.index + 1) % ZaghlolMoment.values.length)
          .toDouble();
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (_disposed || gen != _generation) return;
        input.value = target;
      });
    } else {
      input.value = target;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stateHandle?.dispose();
    _controller.dispose();
  }
}

class RiveMascot extends ZaghlolMascot {
  const RiveMascot({
    super.key,
    required super.moment,
    super.talk = false,
    super.replay = 0,
    required super.size,
    this.loader = loadRiveMascotHandle,
  });

  final RiveMascotLoader loader;

  @override
  State<RiveMascot> createState() => _RiveMascotState();
}

class _RiveMascotState extends State<RiveMascot> {
  RiveMascotHandle? _handle;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final handle = await widget.loader();
      if (!mounted) {
        handle.dispose();
        return;
      }
      RiveMascotProbe.loaded++;
      handle.apply(widget.moment, widget.talk);
      setState(() => _handle = handle);
    } catch (_) {
      RiveMascotProbe.failedToLoad++;
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(RiveMascot old) {
    super.didUpdateWidget(old);
    // T-276: a new moment is an input change on the live state machine; the
    // artboard, controller and render object stay.
    if (old.moment != widget.moment ||
        old.talk != widget.talk ||
        old.replay != widget.replay) {
      _handle?.apply(
        widget.moment,
        widget.talk,
        replay: old.replay != widget.replay,
      );
    }
  }

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _handle;
    if (_failed || h == null) {
      return Image.asset(
        ZaghlolAvatar.stillAsset,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return _PaintGuard(
      onError: () {
        RiveMascotProbe.paintFailed++;
        if (mounted) setState(() => _failed = true);
      },
      child: h.widget,
    );
  }
}
