// FAB-MOCKUP fix: the Android floating Add button must not cover Send.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/ask/presentation/ask_screen.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart';

import '../../budget/presentation/budget_test_support.dart';
import 'ask_screen_test.dart' show FakeEngine, overrides, spend2;

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final lang = locale.languageCode;
    testWidgets('Send and Add do not overlap; tapping Send sends ($lang)', (
      tester,
    ) async {
      await initDateFormatting();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final e = FakeEngine((_, _) async => spend2());
      var added = 0;
      await tester.pumpWidget(
        harness(
          ShellScaffold(
            body: const AskScreen(),
            selected: 3,
            onSelect: (_) {},
            onAdd: () => added++,
            labels: const ['a', 'b', 'c', 'd'],
            addLabel: 'add',
          ),
          locale: locale,
          scale: 1.3,
          overrides: overrides(e),
        ),
      );
      await tester.pump();
      final send = find.byKey(const ValueKey('ask-send'));
      final add = find.byType(ZAddButton);
      expect(tester.getRect(send).overlaps(tester.getRect(add)), isFalse);
      await tester.enterText(find.byType(TextField), 'coffee');
      await tester.pump();
      await tester.tap(send);
      await tester.pump();
      expect(added, 0);
      expect(e.asked, ['coffee']);
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
