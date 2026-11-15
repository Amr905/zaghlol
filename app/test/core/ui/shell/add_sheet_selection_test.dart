// FIX-device-flows: the real shell's Add sheet (a go_router page) must hand
// its tiles a context inside the root Navigator, close itself and then open
// the destination. Before the fix every tile threw and did nothing on device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';

import 'shell_harness.dart';

void main() {
  TabRoots roots() => TabRoots(
    home: (_) => const CounterRoot(tag: 'home'),
    addSelected: (context, action) => closeAddSheetThen(
      context,
      (root) => Navigator.of(root, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              Scaffold(appBar: AppBar(), body: Text('opened:${action.name}')),
        ),
      ),
    ),
  );

  for (final (label, action) in [
    ('Type', AddAction.type),
    ('Say', AddAction.say),
    ('Scan', AddAction.scan),
    ('Asset', AddAction.asset),
  ]) {
    testWidgets('$label tile closes the sheet and opens its screen', (
      tester,
    ) async {
      final router = await pumpShell(tester, roots: roots());
      router.push(AppRoutes.addOverHome);
      await tester.pumpAndSettle();
      expect(find.byType(AddSheet), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('opened:${action.name}'), findsOneWidget);
      expect(find.byType(AddSheet), findsNothing);

      // Closing the destination returns to Home, not to the sheet.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AddSheet), findsNothing);
      expect(find.text('home:0'), findsOneWidget);
    });
  }

  testWidgets('outside a sheet the destination opens at once', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    var opened = false;
    closeAddSheetThen(ctx, (_) => opened = true);
    expect(opened, isTrue);
  });
}
