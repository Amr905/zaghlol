// T-156: mapping step and password prompt, ar (RTL) and en, text scale 1.3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/presentation/statement_mapping_step.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const _roles = {
  StatementColumnRole.date: 'D',
  StatementColumnRole.description: 'T',
  StatementColumnRole.debit: 'O',
  StatementColumnRole.credit: 'I',
  StatementColumnRole.amount: 'A',
  StatementColumnRole.balance: 'B',
  StatementColumnRole.ignore: 'X',
};

StatementMappingLabels labels() => StatementMappingLabels(
  title: 'title',
  hint: 'hint',
  columnTitle: (n) => 'col$n',
  roleName: (r) => _roles[r]!,
  dayFirstLabel: 'dayfirst',
  currencyLabel: 'cur',
  confirm: 'ok',
  invalidHint: 'invalid',
);

StatementTable table(List<StatementColumnRole> suggested) => StatementTable(
  cutPoints: const [150, 500],
  rows: const [
    StatementRawRow(['05/01/2026', 'COFFEE', '45.00']),
  ],
  suggestedRoles: suggested,
  confident: false,
);

Widget host(Widget child, TextDirection dir) => MaterialApp(
  home: Directionality(
    textDirection: dir,
    child: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  for (final dir in TextDirection.values) {
    testWidgets('confirm is disabled until the mapping is usable ($dir)', (
      tester,
    ) async {
      StatementMapping? got;
      await tester.pumpWidget(
        host(
          StatementMappingStep(
            table: table(const [
              StatementColumnRole.date,
              StatementColumnRole.description,
              StatementColumnRole.ignore,
            ]),
            labels: labels(),
            currency: Currency.of('EGP'),
            onConfirm: (m) => got = m,
          ),
          dir,
        ),
      );
      FilledButton button() =>
          tester.widget(find.byKey(const ValueKey('confirm')));
      expect(button().onPressed, isNull);
      expect(find.text('invalid'), findsOneWidget);
      expect(find.text('05/01/2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('role_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull);
      await tester.ensureVisible(find.byKey(const ValueKey('confirm')));
      await tester.tap(find.byKey(const ValueKey('confirm')));
      expect(got!.roles.last, StatementColumnRole.amount);
      expect(got!.currency.code, 'EGP');
      expect(got!.dayFirst, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('password dialog returns text or null ($dir)', (tester) async {
      String? result = 'unset';
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) => TextButton(
              onPressed: () async => result = await askStatementPassword(
                c,
                const StatementPasswordLabels(
                  title: 't',
                  body: 'b',
                  fieldLabel: 'f',
                  wrongHint: 'wrong',
                  confirm: 'go',
                  cancel: 'no',
                ),
                wrong: true,
              ),
              child: const Text('open'),
            ),
          ),
          dir,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('wrong'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('pdfPassword')),
      );
      expect(field.obscureText, isTrue);
      expect(field.enableSuggestions, isFalse);
      await tester.enterText(find.byKey(const ValueKey('pdfPassword')), 'pw');
      await tester.tap(find.byKey(const ValueKey('pdfPasswordOk')));
      await tester.pumpAndSettle();
      expect(result, 'pw');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('no'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  }
}
