@Tags(['golden'])
library;

// T-108: S-21 goldens, ar + en, light + dark. PNGs are not committed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';

import 'charts/charts_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('chart detail golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const RepaintBoundary(
              key: ValueKey('golden-root'),
              child: ChartDetailScreen(
                chart: ChartId.cashFlow,
                code: 'EGP',
                openExplainer: true,
              ),
            ),
            locale: locale,
            dark: dark,
            overrides: chartOverrides(),
          ),
        );
        await tester.pump();
        await tester.pump(
          chartTypingDuration + const Duration(milliseconds: 50),
        );
        await tester.pump();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../goldens/chart_detail_$name.png'),
        );
      });
    }
  }
}
