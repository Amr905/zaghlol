@Tags(['golden'])
library;

// T-102: S-24 and S-25 goldens, ar + en, light + dark. PNGs are not
// committed; run with --update-goldens locally.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/recurring/presentation/bill_edit_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bills_screen.dart';

import '../../budget/presentation/budget_test_support.dart';
import 'bills_screen_test.dart' show full;

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      for (final screen in ['bills', 'bill_edit']) {
        testWidgets('$screen golden $name', (tester) async {
          await initDateFormatting();
          await tester.binding.setSurfaceSize(const Size(390, 1500));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            harness(
              RepaintBoundary(
                key: const ValueKey('golden-root'),
                child: screen == 'bills'
                    ? const BillsScreen()
                    : const BillEditScreen(),
              ),
              locale: locale,
              dark: dark,
              overrides: [
                billsDataProvider.overrideWith((ref) async => full()),
              ],
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byKey(const ValueKey('golden-root')),
            matchesGoldenFile('../../../goldens/${screen}_$name.png'),
          );
        });
      }
    }
  }
}
