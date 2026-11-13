@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'shell_harness.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final p = platform == TargetPlatform.iOS ? 'ios' : 'android';
    for (final v in goldenVariants) {
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
}
