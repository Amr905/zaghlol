// T-195: the expected-salary row, the "is that your salary?" dialog and the
// My salary sheet. Widget behaviour in ar and en, RTL included. Synthetic
// data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/salary/application/salary_service.dart';
import 'package:zaghlol/features/salary/presentation/expected_salary_row.dart';
import 'package:zaghlol/features/salary/presentation/salary_settings.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/presentation/budget_test_support.dart';
import '../../settings/settings_harness.dart';

final Currency egp = Currency.of('EGP');
final ExpectedSalary expected = ExpectedSalary(
  CivilDate(2026, 11, 25),
  Money(egp, 1250000),
  null,
);

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final name = locale.languageCode;

    testWidgets('row ($name): shows title, amount, due day and three '
        'actions; each calls back', (tester) async {
      await initDateFormatting();
      final calls = <String>[];
      await tester.pumpWidget(
        harness(
          SingleChildScrollView(
            child: ExpectedSalaryCard(
              expected: expected,
              onArrived: () => calls.add('arrived'),
              onNotYet: () => calls.add('notYet'),
              onSkip: () => calls.add('skip'),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      final isAr = name == 'ar';
      expect(
        find.text(isAr ? 'المرتب — متوقع' : 'Salary — expected'),
        findsOne,
      );
      expect(find.textContaining(isAr ? '٢٥' : '25'), findsWidgets);
      expect(find.textContaining(isAr ? '١٢٬٥٠٠' : '12,500'), findsWidgets);
      for (final k in ['salary-arrived', 'salary-not-yet', 'salary-skip']) {
        await tester.tap(find.byKey(ValueKey(k)));
      }
      expect(calls, ['arrived', 'notYet', 'skip']);
      // RTL: the title sits right of the amount in Arabic, left in English.
      final title = tester.getTopLeft(
        find.text(isAr ? 'المرتب — متوقع' : 'Salary — expected'),
      );
      final money = tester.getTopLeft(
        find.textContaining(isAr ? '٢٥' : '25').first,
      );
      expect(title.dx > money.dx, isAr);
    });

    testWidgets('dialog ($name): both answers are returned', (tester) async {
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => askSalarySame(context, '10,000 EGP'),
              child: const Text('open'),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SalaryFoundDialog), findsOne);
      expect(find.textContaining('10,000 EGP'), findsOne);
      await tester.tap(find.byKey(const ValueKey('salary-found-yes')));
      await tester.pumpAndSettle();
      expect(find.byType(SalaryFoundDialog), findsNothing);
    });
  }

  group('My salary sheet', () {
    late SettingsHarness h;
    setUp(() => h = SettingsHarness());
    tearDown(() => h.db.close());

    Widget sheet({Locale locale = const Locale('en')}) => h.app(
      const Scaffold(body: SingleChildScrollView(child: SalarySheet())),
      locale: locale,
      overrides: [
        txnLookupsProvider.overrideWith(
          (ref) async => const TxnLookups(categories: [], accounts: []),
        ),
        salaryServiceProvider.overrideWith(
          (ref) async => SalaryService(
            h.db,
            DriftTransactionRepository(TransactionsDao(h.db)),
            zone: const FixedLocalZone(120),
          ),
        ),
      ],
    );

    testWidgets('a bad amount or day shows the error and writes nothing', (
      tester,
    ) async {
      await tester.pumpWidget(sheet());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('salary-amount')), '');
      await tester.tap(find.byKey(const ValueKey('salary-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('salary-invalid')), findsOne);
      await tester.enterText(find.byKey(const ValueKey('salary-amount')), '5');
      await tester.enterText(find.byKey(const ValueKey('salary-day')), '29');
      await tester.tap(find.byKey(const ValueKey('salary-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('salary-invalid')), findsOne);
      expect(
        await SettingsRepository(SettingsDao(h.db)).get(Settings.salaryPlan),
        isNull,
      );
    });

    testWidgets('Arabic-Indic digits are read; Remove only with a plan', (
      tester,
    ) async {
      await tester.pumpWidget(sheet(locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('salary-remove')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('salary-amount')),
        '١٢٥٠٠',
      );
      await tester.enterText(find.byKey(const ValueKey('salary-day')), '٢٥');
      await tester.tap(find.byKey(const ValueKey('salary-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('salary-invalid')), findsNothing);
      final saved = await SettingsRepository(SettingsDao(h.db))
          .get(Settings.salaryPlan);
      expect(saved?.amount, Money(egp, 1250000));
      expect(saved?.day, 25);
      expect(saved?.accountId, isNull);
    });
  });
}
