@Tags(['golden'])
library;

// Insights shell (title, card filter, tabs) goldens, ar + en, light + dark,
// over the Charts, Budget and Bills segments. PNGs are not committed; run
// with --update-goldens to generate them locally.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';

import '../budget/presentation/budget_test_support.dart';
import '../recurring/presentation/bills_screen_test.dart' as bills;
import 'presentation/charts/charts_test_support.dart' as charts;

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      for (final segment in InsightsSegment.values) {
        final name =
            '${segment.name}_${locale.languageCode}_${dark ? 'dark' : 'light'}';
        testWidgets('insights shell golden $name', (tester) async {
          await initDateFormatting();
          await tester.binding.setSurfaceSize(const Size(390, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            harness(
              RepaintBoundary(
                key: const ValueKey('golden-root'),
                child: InsightsScreen(initial: segment),
              ),
              locale: locale,
              dark: dark,
              overrides: [
                ...charts.chartOverrides(currencies: null),
                homeAccountsProvider.overrideWith((ref) async => const []),
                billsDataProvider.overrideWith((ref) async => bills.full()),
              ],
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byKey(const ValueKey('golden-root')),
            matchesGoldenFile('../../goldens/insights_shell_$name.png'),
          );
        });
      }
    }
  }
}
