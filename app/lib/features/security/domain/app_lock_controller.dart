// T-103: the app-lock state machine (FR-SEC-02, A-10). It decides when the
// app is locked and runs the OS check; it holds no secret and stores nothing.
//
// Fail closed: it starts locked (cold start), a clock that went backwards or a
// timeout that can't be read locks at once, and only a successful OS check
// unlocks.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../data/device_security_providers.dart';

/// Wall and monotonic readings, injectable so tests need no real waiting.
/// The monotonic clock can stand still while the phone sleeps and the wall
/// clock can be changed by the user, so the lock uses the larger elapsed time.
class LockClock {
  LockClock({int Function()? wallMs, int Function()? monotonicMs})
    : _wall = wallMs ?? (() => DateTime.now().millisecondsSinceEpoch),
      _mono = monotonicMs ?? _stopwatchMs;

  final int Function() _wall;
  final int Function() _mono;

  int wallMs() => _wall();
  int monotonicMs() => _mono();

  static final Stopwatch _sw = Stopwatch()..start();
  static int _stopwatchMs() => _sw.elapsedMilliseconds;
}

final lockClockProvider = Provider<LockClock>(
  (ref) => LockClock(),
  name: 'lockClockProvider',
);

class AppLockState {
  const AppLockState({
    this.locked = true,
    this.authenticating = false,
    this.autoPrompt = true,
    this.lastOutcome,
  });

  /// True: the content must stay hidden.
  final bool locked;
  final bool authenticating;

  /// One automatic prompt per lock event (design S-05); a failed prompt is not
  /// repeated by itself.
  final bool autoPrompt;
  final AuthOutcome? lastOutcome;

  AppLockState copyWith({
    bool? locked,
    bool? authenticating,
    bool? autoPrompt,
    AuthOutcome? lastOutcome,
    bool clearOutcome = false,
  }) => AppLockState(
    locked: locked ?? this.locked,
    authenticating: authenticating ?? this.authenticating,
    autoPrompt: autoPrompt ?? this.autoPrompt,
    lastOutcome: clearOutcome ? null : (lastOutcome ?? this.lastOutcome),
  );
}

/// Persists the lock setting; a seam so tests need no database.
final appLockWriterProvider = Provider<Future<void> Function(bool)>(
  (ref) => (on) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(Settings.appLockEnabled, on);
  },
  name: 'appLockWriterProvider',
);

enum EnableLockResult { enabled, notSecure, failed, canceled }

class AppLockController extends Notifier<AppLockState> {
  bool _enabled = false;
  int? _bgWallMs;
  int? _bgMonoMs;
  int? _timeoutS;

  @override
  AppLockState build() {
    // Keep the timeout stream subscribed so its value is there when the app
    // comes back (an unwatched stream provider is paused).
    ref.listen<AsyncValue<int>>(appLockTimeoutSProvider, (_, next) {
      _timeoutS = next.asData?.value ?? _timeoutS;
    }, fireImmediately: true);
    return const AppLockState();
  }

  /// The gate feeds the setting here. Turning the lock off unlocks; turning it
  /// on keeps the current state (the user just passed the check to enable it).
  void syncEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _bgWallMs = _bgMonoMs = null;
      state = const AppLockState(locked: false, autoPrompt: false);
    }
  }

  /// Feed every lifecycle change. Ignored while the OS prompt is up: showing
  /// it moves the app to inactive/paused and must not count as leaving.
  void onLifecycle(AppLifecycleState s) {
    if (!_enabled || state.authenticating) return;
    final clock = ref.read(lockClockProvider);
    switch (s) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _bgWallMs ??= clock.wallMs();
        _bgMonoMs ??= clock.monotonicMs();
      case AppLifecycleState.resumed:
        final wall0 = _bgWallMs;
        final mono0 = _bgMonoMs;
        _bgWallMs = _bgMonoMs = null;
        if (wall0 == null || mono0 == null || state.locked) return;
        final wall = clock.wallMs() - wall0;
        final mono = clock.monotonicMs() - mono0;
        // Wall clock moved back: can't trust the elapsed time, so lock.
        final elapsed = wall < 0 ? null : (wall > mono ? wall : mono);
        if (elapsed == null || elapsed >= _timeoutMs()) _lock();
      case AppLifecycleState.inactive:
        break;
    }
  }

  int _timeoutMs() {
    // Not readable yet: lock at once.
    return (_timeoutS ?? 0) * 1000;
  }

  void _lock() {
    state = state.copyWith(locked: true, autoPrompt: true, clearOutcome: true);
  }

  /// Runs the OS check; on success the app unlocks. One check at a time.
  Future<AuthOutcome> unlock(String reason) async {
    if (state.authenticating) return AuthOutcome.canceled;
    final outcome = await _run(reason);
    state = state.copyWith(
      locked: outcome == AuthOutcome.success ? false : state.locked,
      lastOutcome: outcome,
    );
    return outcome;
  }

  Future<AuthOutcome> _run(String reason) async {
    state = state.copyWith(authenticating: true, autoPrompt: false);
    AuthOutcome outcome;
    try {
      outcome = await ref.read(appAuthenticatorProvider).authenticate(reason);
    } on Object {
      outcome = AuthOutcome.failed;
    }
    _bgWallMs = _bgMonoMs = null;
    state = state.copyWith(authenticating: false);
    return outcome;
  }

  /// Settings toggle (FR-ONB-04, used by T-104): turns the lock on only when
  /// the phone has a screen lock and the user passes the OS check once, so a
  /// user can't lock themselves out with a lock they can't open.
  Future<EnableLockResult> enable(String reason) async {
    bool secure;
    try {
      secure = await ref.read(deviceSecurityHostProvider).isDeviceSecure();
    } on Object {
      secure = false;
    }
    if (!secure) return EnableLockResult.notSecure;
    final outcome = await _run(reason);
    if (outcome != AuthOutcome.success) {
      return switch (outcome) {
        AuthOutcome.canceled => EnableLockResult.canceled,
        AuthOutcome.unavailable => EnableLockResult.notSecure,
        _ => EnableLockResult.failed,
      };
    }
    await ref.read(appLockWriterProvider)(true);
    return EnableLockResult.enabled;
  }
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
      name: 'appLockControllerProvider',
    );
