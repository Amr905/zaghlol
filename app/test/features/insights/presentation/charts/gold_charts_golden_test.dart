@Tags(['golden'])
library;

// T-114: Gold charts goldens, ar + en, light + dark. PNGs are not committed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';

import 'charts_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('gold charts golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 5200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const RepaintBoundary(
              key: ValueKey('golden-root'),
              child: ChartsScreen(),
            ),
            locale: locale,
            dark: dark,
            overrides: [...chartOverrides(), ...goldChartOverrides()],
          ),
        );
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
            .read(entitlementStateProvider.notifier)
            .applyVerified(verified: true, status: 'active');
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../../goldens/gold_charts_$name.png'),
        );
      });
    }
  }
}
