@Tags(['golden'])
library;

// T-101: S-22 goldens, ar + en, light + dark. PNGs are not committed; run
// with --update-goldens to generate them locally.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_screen.dart';

import 'budget_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('budget golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const RepaintBoundary(
              key: ValueKey('golden-root'),
              child: BudgetScreen(),
            ),
            locale: locale,
            dark: dark,
            overrides: [
              budgetScreenDataProvider.overrideWith(
                (ref) async => data([egpView(), usdView()]),
              ),
            ],
          ),
        );
        await tester.pump();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../goldens/budget_$name.png'),
        );
      });
    }
  }
}
