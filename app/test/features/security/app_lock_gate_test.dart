import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';
import 'package:zaghlol/features/security/presentation/app_lock_gate.dart';

import 'security_fakes.dart';

const _secret = 'SECRET-HOME-CONTENT';

class _Harness {
  _Harness({
    required this.auth,
    required this.platform,
    this.enabled = true,
    this.locale = const Locale('en'),
  });

  final FakeAuthenticator auth;
  final FakeDevicePlatform platform;
  final bool enabled;
  final Locale locale;
  late final GoRouter router;
  late ProviderContainer container;
  int wall = 1;
  int mono = 1;

  Future<void> pump(WidgetTester tester, {Stream<bool>? enabledStream}) async {
    platform.install();
    router = buildAppRouter(
      TabRoots(
        home: (_) => const Center(child: Text(_secret)),
        insights: (_) => const Center(child: Text('INSIGHTS')),
      ),
    );
    addTearDown(router.dispose);
    final scope = ProviderScope(
      overrides: [
        appAuthenticatorProvider.overrideWithValue(auth),
        appLockEnabledProvider.overrideWith(
          (ref) => enabledStream ?? Stream.value(enabled),
        ),
        appLockTimeoutSProvider.overrideWith((ref) => Stream.value(60)),
        lockClockProvider.overrideWithValue(
          LockClock(wallMs: () => wall, monotonicMs: () => mono),
        ),
      ],
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        routerConfig: router,
        builder: (context, child) => AppLockGate(child: child!),
      ),
    );
    await tester.pumpWidget(scope);
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppLockGate)),
    );
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  setUp(() => rootedWarningShown = false);

  testWidgets('lock off: content shows, no prompt, window not secure', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator(),
      platform: FakeDevicePlatform(),
      enabled: false,
    );
    await h.pump(tester);
    expect(find.text(_secret), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-unlock')), findsNothing);
    expect(h.auth.reasons, isEmpty);
    expect(h.platform.secureWindowCalls, [false]);
  });

  testWidgets('lock on: cold start hides content, prompts once, window secure '
      '(AC: app switcher blank)', (tester) async {
    final h = _Harness(
      auth: FakeAuthenticator([AuthOutcome.failed]),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester);
    expect(find.text(_secret), findsNothing);
    expect(find.byKey(const ValueKey('lock-unlock')), findsOneWidget);
    expect(h.auth.reasons, hasLength(1));
    expect(h.platform.secureWindowCalls, contains(true));
    expect(find.byKey(const ValueKey('lock-message')), findsOneWidget);
    // A failed prompt is not repeated by itself.
    await tester.pump(const Duration(seconds: 2));
    expect(h.auth.reasons, hasLength(1));
  });

  testWidgets('retry button runs the check again; success shows the content', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator([AuthOutcome.failed, AuthOutcome.success]),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester);
    await tester.tap(find.byKey(const ValueKey('lock-unlock')));
    await tester.pump();
    await tester.pump();
    expect(find.text(_secret), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-unlock')), findsNothing);
  });

  testWidgets('inactive state shows a blank cover over the content', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator(),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester);
    expect(find.text(_secret), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text(_secret), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('background longer than the timeout re-locks and prompts', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator(),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester);
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    h.wall += 61000;
    h.mono += 61000;
    for (final s in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    await tester.pump();
    expect(h.auth.reasons, hasLength(2));
  });

  testWidgets('a deep link while locked lands only after unlock (FU-125)', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator([AuthOutcome.canceled, AuthOutcome.success]),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester);
    h.router.go('zaghlol://budget');
    await tester.pump();
    await tester.pump();
    expect(find.text('INSIGHTS'), findsNothing);
    expect(find.text(_secret), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lock-unlock')));
    await tester.pump();
    await tester.pump();
    expect(find.text('INSIGHTS'), findsOneWidget);
  });

  testWidgets('an unreadable setting fails closed (locked)', (tester) async {
    final h = _Harness(
      auth: FakeAuthenticator([AuthOutcome.failed]),
      platform: FakeDevicePlatform(),
    );
    await h.pump(tester, enabledStream: Stream<bool>.error(StateError('db')));
    expect(find.text(_secret), findsNothing);
    expect(find.byKey(const ValueKey('lock-unlock')), findsOneWidget);
  });

  testWidgets('a failing setSecureWindow does not unlock or crash', (
    tester,
  ) async {
    final platform = FakeDevicePlatform()..throwOnSecureWindow = true;
    final h = _Harness(
      auth: FakeAuthenticator([AuthOutcome.failed]),
      platform: platform,
    );
    await h.pump(tester);
    expect(find.text(_secret), findsNothing);
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('lock screen shows localized, direction-aware text '
        '(${locale.languageCode})', (tester) async {
      final h = _Harness(
        auth: FakeAuthenticator([AuthOutcome.unavailable]),
        platform: FakeDevicePlatform(),
        locale: locale,
      );
      await h.pump(tester);
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(find.text(l10n.appLockTitle), findsOneWidget);
      expect(find.text(l10n.appLockUnavailable), findsOneWidget);
      expect(find.text(l10n.appLockUnlock), findsOneWidget);
      final dir = Directionality.of(
        tester.element(find.text(l10n.appLockTitle)),
      );
      expect(
        dir,
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
    });
  }

  testWidgets('rooted device: one warning dialog, app still usable', (
    tester,
  ) async {
    final h = _Harness(
      auth: FakeAuthenticator(),
      platform: FakeDevicePlatform(rooted: true),
      enabled: false,
    );
    await h.pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Weaker protection on this phone'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(_secret), findsOneWidget);
  });

  testWidgets('not rooted: no warning', (tester) async {
    final h = _Harness(
      auth: FakeAuthenticator(),
      platform: FakeDevicePlatform(),
      enabled: false,
    );
    await h.pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Weaker protection on this phone'), findsNothing);
  });
}
