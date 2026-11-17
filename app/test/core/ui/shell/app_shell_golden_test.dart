@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'shell_harness.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final p = platform == TargetPlatform.iOS ? 'ios' : 'android';
    for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
      testWidgets('app shell golden ${p}_${v.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpShell(
          tester,
          locale: v.locale,
          platform: platform,
          dark: v.dark,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../../goldens/app_shell_${p}_${v.name}.png'),
        );
      });
    }
  }

  // batch-29 minor: 4 destinations + Add at 320 dp, text scale 1.3.
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final p = platform == TargetPlatform.iOS ? 'ios' : 'android';
    for (final lang in ['ar', 'en']) {
      testWidgets('app shell narrow golden ${p}_$lang', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpShell(
          tester,
          locale: Locale(lang),
          platform: platform,
          textScale: 1.3,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../../goldens/app_shell_narrow_${p}_$lang.png'),
        );
      });
    }
  }
}
