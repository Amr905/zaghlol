// T-080 S-13 widget tests: add, edit, validation, errors, unsaved, ar/en,
// text scale 1.3. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';

import '../detail_edit_harness.dart';
import '../list/list_harness.dart';

void main() {
  setUpAll(initDateFormatting);

  Future<void> chooseCategory(WidgetTester tester, String name) async {
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('add: default account is Cash, amount parsed exactly', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    expect(find.textContaining('NBE Visa'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '١٢٣٫٥٠');
    await chooseCategory(tester, 'Food');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final leg = ed.added.single.single;
    expect(leg.amount.minor, 12350);
    expect(leg.amount.currency.code, 'EGP');
    expect(leg.direction, TxnDirection.expense);
    expect(leg.accountId, 'acc1');
    expect(leg.categoryId, 'food');
    expect(find.text('open'), findsOneWidget, reason: 'sheet closed');
  });

  testWidgets('add income picks the income direction', (tester) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.text('Add income'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '10');
    await chooseCategory(tester, 'Bills');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ed.added.single.single.direction, TxnDirection.income);
  });

  testWidgets('empty form shows amount and category errors, saves nothing', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount above zero'), findsOneWidget);
    expect(find.text('Choose a category'), findsOneWidget);
    expect(ed.added, isEmpty);
  });

  testWidgets('too many decimals is refused for the currency', (tester) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.enterText(find.byType(TextField).first, '1.234');
    await chooseCategory(tester, 'Food');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('allows 2 decimals'), findsOneWidget);
    expect(ed.added, isEmpty);
  });

  testWidgets('save failure keeps the form and shows the banner', (
    tester,
  ) async {
    final ed = FakeEditor()..failWith = TransactionsException('TXN_INVALID');
    await pumpEditor(tester, ed);
    await tester.enterText(find.byType(TextField).first, '50');
    await chooseCategory(tester, 'Food');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't save"), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('transfer needs two different accounts', (tester) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('NBE Visa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick two different accounts'), findsOneWidget);
    expect(ed.added, isEmpty);
  });

  testWidgets('transfer to an account in another currency stores one leg', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final legs = ed.added.single;
    expect(legs, hasLength(1));
    expect(legs.single.direction, TxnDirection.transferOut);
    expect(legs.single.categoryId, isNull);
  });

  testWidgets('edit prefills; an amount change is sent as exact minor units', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed, existing: txnRec('a', minor: 45000));
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('450.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '300.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final (id, edit) = ed.updates.single;
    expect(id, 'a');
    expect(edit.amount!.minor, 30050);
    expect(edit.categoryId, isNull);
    expect(edit.note, isNull);
  });

  testWidgets('edit that removed links shows the notice', (tester) async {
    final ed = FakeEditor()..removedLinks = ['l1'];
    await pumpEditor(tester, ed, existing: txnRec('a', minor: 45000));
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('leaving with unsaved input asks to discard', (tester) async {
    final ed = FakeEditor();
    await pumpEditor(tester, ed);
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('clean form closes without asking', (tester) async {
    await pumpEditor(tester, FakeEditor());
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('shared message text is shown for review', (tester) async {
    await pumpEditor(tester, FakeEditor(), rawText: 'SYNTHETIC MESSAGE');
    expect(find.text('SYNTHETIC MESSAGE'), findsOneWidget);
    expect(find.textContaining('Check it and save'), findsOneWidget);
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('renders in $locale at text scale 1.3 without overflow', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        FakeEditor(),
        locale: locale,
        textScale: 1.3,
        rawText: 'SYNTHETIC',
      );
      expect(tester.takeException(), isNull);
      if (locale.languageCode == 'ar') {
        expect(
          Directionality.of(tester.element(find.byType(Scaffold).last)),
          TextDirection.rtl,
        );
      }
    });
  }
}
