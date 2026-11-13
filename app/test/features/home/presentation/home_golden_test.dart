@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'home_harness.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final p = platform == TargetPlatform.iOS ? 'ios' : 'android';
    for (final v in goldenVariants) {
      testWidgets('home golden ${p}_${v.name}', (tester) async {
        await pumpHome(
          tester,
          locale: v.locale,
          platform: platform,
          dark: v.dark,
          value: model(review: 3),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_${p}_${v.name}.png'),
        );
      });
      testWidgets('home empty golden ${p}_${v.name}', (tester) async {
        await pumpHome(
          tester,
          locale: v.locale,
          platform: platform,
          dark: v.dark,
          value: model(currencies: [], recent: []),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_empty_${p}_${v.name}.png'),
        );
      });
    }
  }
}
