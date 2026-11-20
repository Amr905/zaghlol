@Tags(['golden'])
library;

// T-187 / AC5: Home and the charts screen with amounts hidden, ar + en,
// light + dark. PNGs are produced by the app-regen workflow, not locally.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';

import '../../support/golden_matrix.dart';
import '../../support/hide_amounts_support.dart';
import '../home/presentation/home_harness.dart';
import '../insights/presentation/charts/charts_test_support.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('home hidden golden ${v.name}', (tester) async {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      await pumpHome(
        tester,
        locale: v.locale,
        platform: TargetPlatform.android,
        dark: v.dark,
        value: model(review: 3),
        hideAmounts: h,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_hidden_${v.name}.png'),
      );
    });

    testWidgets('charts hidden golden ${v.name}', (tester) async {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      await initDateFormatting();
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          const RepaintBoundary(
            key: ValueKey('golden-root'),
            child: ChartsScreen(),
          ),
          locale: v.locale,
          dark: v.dark,
          overrides: chartOverrides(),
          hideAmounts: h,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('../../goldens/charts_hidden_${v.name}.png'),
      );
    });
  }
}
