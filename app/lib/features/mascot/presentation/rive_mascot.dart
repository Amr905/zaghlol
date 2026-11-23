// T-099 / T-088: plays assets/rive/zaghlol.riv. Names are the contract in
// docs/02-design/mascot-rive-handoff.md. If the file fails to load, shows the
// still so the app never breaks.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rive/rive.dart' as rive;

import 'zaghlol_avatar.dart' show ZaghlolAvatar;
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

class RiveMascot extends ZaghlolMascot {
  const RiveMascot({
    super.key,
    required super.moment,
    super.talk = false,
    required super.size,
  });

  @override
  State<RiveMascot> createState() => _RiveMascotState();
}

class _RiveMascotState extends State<RiveMascot> {
  rive.RiveWidgetController? _controller;
  rive.CallbackHandler? _stateHandle;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await _loadSharedFile();
      final controller = rive.RiveWidgetController(
        file,
        artboardSelector: rive.ArtboardSelector.byName(kRiveArtboard),
        stateMachineSelector: rive.StateMachineSelector.byName(
          kRiveStateMachine,
        ),
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      RiveMascotProbe.loaded++;
      if (RiveMascotProbe.recordStates) {
        _stateHandle = controller.stateMachine.onStateChanged(
          RiveMascotProbe.recordState,
        );
      }
      setState(() {
        _controller = controller;
      });
      _push();
    } catch (_) {
      RiveMascotProbe.failedToLoad++;
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(RiveMascot old) {
    super.didUpdateWidget(old);
    _push();
  }

  // Legacy state machine inputs: stable and enough for one number + two flags.
  // ignore_for_file: deprecated_member_use, invalid_use_of_internal_member
  void _push() {
    final sm = _controller?.stateMachine;
    if (sm == null) return;
    sm.number(kRiveInputState)?.value = widget.moment.index.toDouble();
    sm.boolean(kRiveInputTalk)?.value = widget.talk;
    sm.boolean(kRiveInputReduceMotion)?.value = false;
  }

  @override
  void dispose() {
    _stateHandle?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null) {
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
      child: rive.RiveWidget(controller: c, fit: rive.Fit.contain),
    );
  }
}
