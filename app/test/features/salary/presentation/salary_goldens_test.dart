@Tags(['golden'])
library;

// T-195 AC4: ar + en goldens (light, dark) of the expected-salary row, the
// "is that your salary?" nudge dialog and the My salary sheet. RTL is in the
// Arabic ones. Update with --update-goldens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/salary/application/salary_service.dart';
import 'package:zaghlol/features/salary/presentation/expected_salary_row.dart';
import 'package:zaghlol/features/salary/presentation/salary_settings.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/presentation/budget_test_support.dart';

void main() {
  final expected = ExpectedSalary(
    CivilDate(2026, 11, 25),
    Money(Currency.of('EGP'), 1250000),
    null,
  );
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';

      Future<void> golden(
        WidgetTester tester,
        String file,
        Widget child, {
        List<Override> overrides = const [],
        Size size = const Size(390, 360),
      }) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            RepaintBoundary(key: const ValueKey('golden-root'), child: child),
            locale: locale,
            dark: dark,
            overrides: overrides,
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../goldens/$file$name.png'),
        );
      }

      testWidgets('expected salary row golden $name', (tester) async {
        await golden(
          tester,
          'salary_expected_',
          Padding(
            padding: const EdgeInsets.all(16),
            child: ExpectedSalaryCard(
              expected: expected,
              onArrived: () {},
              onNotYet: () {},
              onSkip: () {},
            ),
          ),
          size: const Size(390, 430),
        );
      });

      testWidgets('salary nudge dialog golden $name', (tester) async {
        await golden(
          tester,
          'salary_found_',
          Center(
            child: SalaryFoundDialog(amount: '12,500 EGP', onAnswer: (_) {}),
          ),
          size: const Size(390, 360),
        );
      });

      testWidgets('my salary sheet golden $name', (tester) async {
        await golden(
          tester,
          'salary_sheet_',
          const Padding(
            padding: EdgeInsets.all(24),
            child: SingleChildScrollView(child: SalarySheet()),
          ),
          overrides: [
            salaryPlanProvider.overrideWith((ref) => Stream.value(null)),
            txnLookupsProvider.overrideWith(
              (ref) async => const TxnLookups(
                categories: [],
                accounts: [
                  TxnAccount(
                    id: 'a1',
                    label: 'Synthetic bank',
                    last4: '1234',
                    institutionCode: 'BNK',
                    currencyCode: 'EGP',
                  ),
                ],
              ),
            ),
          ],
          size: const Size(390, 620),
        );
      });
    }
  }
}
