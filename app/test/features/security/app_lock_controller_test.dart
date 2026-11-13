import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';

import 'security_fakes.dart';

/// Lets the overridden timeout stream deliver its value.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late int wall;
  late int mono;
  late FakeAuthenticator auth;
  late ProviderContainer c;

  ProviderContainer make({int timeoutS = 60, FakeAuthenticator? a}) {
    auth = a ?? FakeAuthenticator();
    final container = ProviderContainer(
      overrides: [
        appAuthenticatorProvider.overrideWithValue(auth),
        lockClockProvider.overrideWithValue(
          LockClock(wallMs: () => wall, monotonicMs: () => mono),
        ),
        appLockTimeoutSProvider.overrideWith((ref) => Stream.value(timeoutS)),
      ],
    );
    addTearDown(container.dispose);
    // A listener keeps the controller (and its timeout subscription) live.
    container.listen(appLockControllerProvider, (_, _) {});
    return container;
  }

  AppLockController ctl() => c.read(appLockControllerProvider.notifier);
  AppLockState st() => c.read(appLockControllerProvider);

  Future<void> background(int ms, {int? wallMs}) async {
    ctl().onLifecycle(AppLifecycleState.inactive);
    ctl().onLifecycle(AppLifecycleState.hidden);
    ctl().onLifecycle(AppLifecycleState.paused);
    wall += wallMs ?? ms;
    mono += ms;
    ctl().onLifecycle(AppLifecycleState.resumed);
  }

  setUp(() async {
    wall = 1000000;
    mono = 5000;
    c = make();
    // Let the timeout stream deliver its value.
    await settle();
  });

  test('cold start is locked until the OS check passes', () async {
    ctl().syncEnabled(true);
    expect(st().locked, isTrue);
    expect(await ctl().unlock('why'), AuthOutcome.success);
    expect(st().locked, isFalse);
    expect(auth.reasons, ['why']);
  });

  test(
    'a failed or cancelled check keeps it locked and does not loop',
    () async {
      c = make(a: FakeAuthenticator([AuthOutcome.failed, AuthOutcome.success]));
      await settle();
      ctl().syncEnabled(true);
      await ctl().unlock('r');
      expect(st().locked, isTrue);
      expect(st().lastOutcome, AuthOutcome.failed);
      expect(st().autoPrompt, isFalse);
      await ctl().unlock('r');
      expect(st().locked, isFalse);
    },
  );

  test('lock off: never locked', () {
    ctl().syncEnabled(false);
    expect(st().locked, isFalse);
    ctl().onLifecycle(AppLifecycleState.paused);
    mono += 10 * 60 * 1000;
    wall += 10 * 60 * 1000;
    ctl().onLifecycle(AppLifecycleState.resumed);
    expect(st().locked, isFalse);
  });

  test('re-locks after the background timeout, not before (A-10)', () async {
    ctl().syncEnabled(true);
    await ctl().unlock('r');
    await background(59 * 1000);
    expect(st().locked, isFalse);
    await background(60 * 1000);
    expect(st().locked, isTrue);
    expect(st().autoPrompt, isTrue);
  });

  test('timeout 0 locks at once', () async {
    c = make(timeoutS: 0);
    await settle();
    ctl().syncEnabled(true);
    await ctl().unlock('r');
    await background(1);
    expect(st().locked, isTrue);
  });

  test('inactive alone (a system sheet) never locks', () async {
    ctl().syncEnabled(true);
    await ctl().unlock('r');
    ctl().onLifecycle(AppLifecycleState.inactive);
    mono += 10 * 60 * 1000;
    wall += 10 * 60 * 1000;
    ctl().onLifecycle(AppLifecycleState.resumed);
    expect(st().locked, isFalse);
  });

  test(
    'a monotonic clock that stood still in sleep still locks via wall',
    () async {
      ctl().syncEnabled(true);
      await ctl().unlock('r');
      await background(0, wallMs: 5 * 60 * 1000);
      expect(st().locked, isTrue);
    },
  );

  test('wall clock moved back: locks (fail closed)', () async {
    ctl().syncEnabled(true);
    await ctl().unlock('r');
    await background(1000, wallMs: -3600 * 1000);
    expect(st().locked, isTrue);
  });

  test('the OS prompt moving the app to paused does not lock or arm', () async {
    ctl().syncEnabled(true);
    final pending = ctl().unlock('r');
    ctl().onLifecycle(AppLifecycleState.paused);
    mono += 10 * 60 * 1000;
    wall += 10 * 60 * 1000;
    ctl().onLifecycle(AppLifecycleState.resumed);
    await pending;
    expect(st().locked, isFalse);
    // The paused seen during the prompt must not count as "left the app".
    ctl().onLifecycle(AppLifecycleState.resumed);
    expect(st().locked, isFalse);
  });

  test('two unlock calls at once start one OS check', () async {
    ctl().syncEnabled(true);
    final a = ctl().unlock('r');
    final b = ctl().unlock('r');
    await Future.wait([a, b]);
    expect(auth.reasons, hasLength(1));
  });

  test(
    'an authenticator that throws is a failed check, never a pass',
    () async {
      c = ProviderContainer(
        overrides: [
          appAuthenticatorProvider.overrideWithValue(_Throwing()),
          appLockTimeoutSProvider.overrideWith((ref) => Stream.value(60)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(appLockControllerProvider, (_, _) {});
      ctl().syncEnabled(true);
      expect(await ctl().unlock('r'), AuthOutcome.failed);
      expect(st().locked, isTrue);
    },
  );

  test(
    'turning the lock off unlocks; on again keeps the session open',
    () async {
      ctl().syncEnabled(true);
      ctl().syncEnabled(false);
      expect(st().locked, isFalse);
      ctl().syncEnabled(true);
      expect(st().locked, isFalse);
    },
  );

  group('enable (settings toggle, FR-ONB-04)', () {
    late List<bool> written;

    Future<EnableLockResult> run(
      FakeAuthenticator a, {
      bool secure = true,
    }) async {
      FakeDevicePlatform(secure: secure).install();
      written = [];
      c = ProviderContainer(
        overrides: [
          appAuthenticatorProvider.overrideWithValue(a),
          appLockTimeoutSProvider.overrideWith((ref) => Stream.value(60)),
          appLockWriterProvider.overrideWithValue(
            (on) async => written.add(on),
          ),
        ],
      );
      addTearDown(c.dispose);
      return ctl().enable('r');
    }

    test('no phone screen lock: refused, nothing written, no prompt', () async {
      final a = FakeAuthenticator();
      expect(await run(a, secure: false), EnableLockResult.notSecure);
      expect(written, isEmpty);
      expect(a.reasons, isEmpty);
    });

    test('check failed or cancelled: nothing written', () async {
      expect(
        await run(FakeAuthenticator([AuthOutcome.failed])),
        EnableLockResult.failed,
      );
      expect(
        await run(FakeAuthenticator([AuthOutcome.canceled])),
        EnableLockResult.canceled,
      );
      expect(written, isEmpty);
    });

    test('check passed: written once', () async {
      expect(await run(FakeAuthenticator()), EnableLockResult.enabled);
      expect(written, [true]);
    });
  });
}

class _Throwing implements AppAuthenticator {
  @override
  Future<AuthOutcome> authenticate(String reason) => throw StateError('x');
}
