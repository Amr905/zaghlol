@Tags(['golden'])
library;

// T-107: S-20 goldens, ar + en, light + dark. PNGs are not committed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';

import 'charts_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('charts golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const RepaintBoundary(
              key: ValueKey('golden-root'),
              child: ChartsScreen(),
            ),
            locale: locale,
            dark: dark,
            overrides: chartOverrides(),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../../goldens/charts_$name.png'),
        );
      });
    }
  }
}
