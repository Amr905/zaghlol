// T-111: goldens for S-50 (ar/en x light/dark). Tagged; PNGs are not committed.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ask/presentation/ask_screen.dart';

import 'ask_screen_test.dart' show FakeEngine, compare, pump;

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in const [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('S-50 empty $name', (tester) async {
        await pump(
          tester,
          FakeEngine((_, _) async => compare()),
          locale: locale,
          dark: dark,
        );
        await expectLater(
          find.byType(AskScreen),
          matchesGoldenFile('goldens/ask_empty_$name.png'),
        );
      });
      testWidgets('S-50 answer $name', (tester) async {
        await pump(
          tester,
          FakeEngine((_, _) async => compare()),
          locale: locale,
          dark: dark,
        );
        await tester.tap(find.byType(ActionChip).first);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(AskScreen),
          matchesGoldenFile('goldens/ask_answer_$name.png'),
        );
      });
    }
  }
}
