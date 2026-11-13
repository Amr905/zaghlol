// T-103: wraps the whole routed app (MaterialApp.router `builder`). While the
// lock is on and engaged, the app content stays mounted (state and the
// current route survive, so a deep link lands after unlock, FU-125) but is
// not painted, hit-tested or exposed to accessibility, and the lock screen
// covers it. It also keeps the native secure window in step with the setting
// and shows the rooted-device warning once per process (FR-SEC-07).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/settings/settings_providers.dart';
import '../data/device_security_providers.dart';
import '../domain/app_lock_controller.dart';
import 'lock_screen.dart';

/// The warning is shown once per process; a test resets it.
@visibleForTesting
bool rootedWarningShown = false;

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _inactive = false;
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AsyncValue<bool>>(
      appLockEnabledProvider,
      (_, next) => _onEnabled(next),
      fireImmediately: true,
    );
    // Never leave a keyboard open behind the lock.
    ref.listenManual<AppLockState>(appLockControllerProvider, (prev, next) {
      if (next.locked && !(prev?.locked ?? false)) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
    unawaited(_maybeWarnRooted());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// null: not known yet. An unreadable setting counts as "on" (fail closed).
  bool? _enabled(AsyncValue<bool> v) =>
      v.when(data: (e) => e, loading: () => null, error: (_, _) => true);

  void _onEnabled(AsyncValue<bool> v) {
    final enabled = _enabled(v);
    if (enabled == null) return;
    ref.read(appLockControllerProvider.notifier).syncEnabled(enabled);
    _applySecureWindow(enabled);
  }

  void _applySecureWindow(bool secure) => unawaited(_setSecureWindow(secure));

  Future<void> _setSecureWindow(bool secure) async {
    try {
      await ref.read(deviceSecurityHostProvider).setSecureWindow(secure);
    } on Object {
      // The Dart-side cover below still hides the content.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inactive = state != AppLifecycleState.resumed;
    ref.read(appLockControllerProvider.notifier).onLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      // Re-assert after the OS may have reset the window.
      final enabled = _enabled(ref.read(appLockEnabledProvider));
      if (enabled != null) _applySecureWindow(enabled);
    }
    if (inactive != _inactive) setState(() => _inactive = inactive);
  }

  Future<void> _maybeWarnRooted() async {
    final rooted = await ref.read(deviceRootedProvider.future);
    if (!rooted || rootedWarningShown || !mounted) return;
    // Wait until the router has a navigator to show the dialog on.
    for (var i = 0; i < 100; i++) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        rootedWarningShown = true;
        final l10n = AppLocalizations.of(ctx);
        await showDialog<void>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: Text(l10n.appLockRootedTitle),
            content: Text(l10n.appLockRootedBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: Text(l10n.appLockRootedOk),
              ),
            ],
          ),
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
  }

  void _schedulePrompt() {
    if (_promptScheduled) return;
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      if (!mounted || _inactive) return;
      final lock = ref.read(appLockControllerProvider);
      if (lock.locked && lock.autoPrompt && !lock.authenticating) {
        unawaited(_unlock());
      }
    });
  }

  Future<void> _unlock() async {
    final reason = AppLocalizations.of(context).appLockReason;
    await ref.read(appLockControllerProvider.notifier).unlock(reason);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled(ref.watch(appLockEnabledProvider));
    final lock = ref.watch(appLockControllerProvider);
    // Not known yet: cover (blank); known and off: nothing.
    final unknown = enabled == null;
    final engaged = enabled == true && lock.locked;
    final hidden = unknown || engaged || (enabled == true && _inactive);
    if (engaged) {
      if (!_inactive) _schedulePrompt();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: hidden,
          child: TickerMode(enabled: !hidden, child: widget.child),
        ),
        if (hidden)
          Positioned.fill(
            child: engaged && !_inactive
                ? LockScreen(
                    outcome: lock.lastOutcome,
                    busy: lock.authenticating,
                    onUnlock: () => unawaited(_unlock()),
                  )
                : _BlankCover(),
          ),
      ],
    );
  }
}

class _BlankCover extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: const SizedBox.expand(),
  );
}
