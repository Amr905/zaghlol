@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'shell_harness.dart';

void main() {
  // T-203: one shared bar (D-77), so one golden set: ar + en x light + True
  // Black dark, plus x1.3.
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    testWidgets('app shell golden ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester, locale: v.locale, dark: v.dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/app_shell_${v.name}.png'),
      );
    });
  }

  // batch-29 minor: 4 destinations + Add at 320 dp, text scale 1.3.
  for (final lang in ['ar', 'en']) {
    testWidgets('app shell narrow golden $lang', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester, locale: Locale(lang), textScale: 1.3);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/app_shell_narrow_$lang.png'),
      );
    });
  }
}
