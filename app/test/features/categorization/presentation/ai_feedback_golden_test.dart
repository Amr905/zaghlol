@Tags(['golden'])
library;

// T-361 goldens: row and suggestion bar, ar/en, light/dark, 130 %. PNGs are
// generated on demand (`flutter test --update-goldens --tags golden`) and
// not committed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';

import 'ai_feedback_harness.dart';

void main() {
  setUpAll(initDateFormatting);
  for (final loc in [const Locale('ar', 'EG'), const Locale('en')]) {
    for (final dark in [false, true]) {
      final n = '${loc.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('chip row and controls $n', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await pumpApp(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(aiRec()),
              const SizedBox(height: 16),
              bar(loc.languageCode),
            ],
          ),
          locale: loc,
          dark: dark,
          scale: 1.3,
        );
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/ai_chip_$n.png'),
        );
      });
    }
  }
}
