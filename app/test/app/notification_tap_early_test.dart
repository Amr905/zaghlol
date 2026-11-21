// T-193 AC5 finding: a tap event that arrives before the root navigator exists
// waits for it (bounded) instead of being dropped.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol/app/notification_taps.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';

class _Source implements NotificationTapSource {
  final controller = StreamController<String>.broadcast();

  @override
  Future<String?> takeLaunchRoute() async => null;

  @override
  Stream<String> get taps => controller.stream;
}

void main() {
  testWidgets('a tap before the navigator waits, then opens', (tester) async {
    final source = _Source();
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/insights', builder: (_, _) => const SizedBox()),
      ],
    );
    final ready = ValueNotifier(false);
    addTearDown(() {
      ready.dispose();
      unawaited(source.controller.close());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationTapSourceProvider.overrideWithValue(source),
          appRouterProvider.overrideWithValue(router),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NotificationTapLifecycle(
            child: ValueListenableBuilder<bool>(
              valueListenable: ready,
              builder: (_, on, _) => on
                  ? MaterialApp(
                      navigatorKey: rootNavigatorKey,
                      home: const SizedBox(),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    expect(rootNavigatorKey.currentContext, isNull);

    source.controller.add('/insights');
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      router.routeInformationProvider.value.uri.path,
      '/',
      reason: 'no navigator yet: not opened, and not dropped either',
    );

    ready.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/insights');
  });

  testWidgets('a tap that never finds a navigator gives up quietly', (
    tester,
  ) async {
    final source = _Source();
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    addTearDown(() => unawaited(source.controller.close()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationTapSourceProvider.overrideWithValue(source),
          appRouterProvider.overrideWithValue(router),
        ],
        child: const NotificationTapLifecycle(child: SizedBox()),
      ),
    );
    source.controller.add('/insights');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox()); // dispose while waiting is safe
    expect(tester.takeException(), isNull);
  });
}
