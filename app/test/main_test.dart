import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/main.dart';

void main() {
  testWidgets('app renders the routed shell with four tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: const ZaghlolApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });
}
