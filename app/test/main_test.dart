import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZBottomBar;
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

    expect(find.byType(ZBottomBar), findsOneWidget);
    expect(find.byType(InkWell), findsAtLeastNWidgets(5));
  });
}
