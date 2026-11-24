// T-238 / E2E-11: app lock and the secure window, in the real app on the
// emulator. The lock is switched on through the app's settings provider (the
// OS credential check that Preferences runs cannot be passed on a CI
// emulator), with the timeout at 0 so any background trip locks. The test
// then sends the app through paused -> resumed, and expects the lock screen.
// While the lock is on, .github/scripts/e2e-settings-device.sh looks at
// `dumpsys window` for the window's FLAG_SECURE (the app switcher's snapshot
// is hidden by it) when the test prints E2E11 SECURE_ON_CHECK, and again for
// its absence after the lock is turned off (E2E11 SECURE_OFF_CHECK).
// Synthetic data only.
//
// Run: flutter test integration_test/e2e_lock_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';
import 'package:zaghlol/main.dart' as app;

import 'support/e2e_settings_common.dart';

void main() {
  final e = E2e('E2E11');

  testWidgets('lock engages after a background trip; secure window follows', (
    t,
  ) async {
    await e.guarded(t, () async {
      await e.seedReturningUser();
      e.captureFlutterErrors();

      await app.main();
      e.say('MAIN_RETURNED');
      await e.waitFor(t, find.text('Home'), what: 'Home');
      await e.settle(t, 2000);
      final lockKey = find.byKey(const ValueKey('lock-unlock'));
      e.check(!e.found(lockKey), 'no lock screen while the lock is off');
      await e.shot(t, '01-lock-off');

      // ---- Lock on (timeout 0: lock at once after a background trip).
      final repo = await e.container().read(settingsRepositoryProvider.future);
      await repo.set(Settings.appLockTimeoutS, 0);
      await repo.set(Settings.appLockEnabled, true);
      await e.settle(t, 2000);
      e.check(
        !e.container().read(appLockControllerProvider).locked,
        'turning the lock on does not lock the user out at once',
      );

      // ---- Background and foreground.
      final b = WidgetsBinding.instance;
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // No frames are scheduled while paused: wait on the clock, not pump().
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await e.settle(t, 2000);
      e.check(
        e.container().read(appLockControllerProvider).locked,
        'the controller is locked after the background trip',
      );
      await e.waitFor(t, lockKey, what: 'the lock screen');
      await e.shot(t, '02-locked');

      // ---- The window is secure while the lock is on (checked by the script).
      e.say('SECURE_ON_CHECK');
      await e.settle(t, 12000);
      e.check(e.found(lockKey), 'the lock screen is still there');

      // ---- Lock off: the lock screen goes and the window is not secure.
      await repo.set(Settings.appLockEnabled, false);
      await e.settle(t, 2500);
      e.check(!e.found(lockKey), 'the lock screen goes when the lock is off');
      e.check(
        !e.container().read(appLockControllerProvider).locked,
        'the controller is unlocked when the lock is off',
      );
      await e.shot(t, '03-lock-off-again');
      e.say('SECURE_OFF_CHECK');
      await e.settle(t, 12000);
      e.finish();
    });
  });
}
