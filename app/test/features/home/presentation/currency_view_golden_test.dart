@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'currency_view_harness.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('currency view golden ${v.name}', (tester) async {
      await pumpView(
        tester,
        viewApp(iso: 'USD', env: ViewEnv(), locale: v.locale, dark: v.dark),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/currency_view_${v.name}.png'),
      );
    });
    testWidgets('currency view empty golden ${v.name}', (tester) async {
      await pumpView(
        tester,
        viewApp(iso: 'ZZZ', env: ViewEnv(), locale: v.locale, dark: v.dark),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/currency_view_empty_${v.name}.png'),
      );
    });
  }
}
