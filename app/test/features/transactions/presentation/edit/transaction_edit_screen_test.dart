// T-080 S-13 widget tests: add, edit, validation, errors, unsaved, ar/en,
// text scale 1.3. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/edit/transaction_edit_screen.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_form.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../detail_edit_harness.dart';
import '../list/list_harness.dart';

void main() {
  setUpAll(initDateFormatting);

  for (final loc in const [Locale('en'), Locale('ar')]) {
    testWidgets(
      'category picker never shows icon names (${loc.languageCode})',
      (tester) async {
        await pumpEditor(tester, FakeEditor(), locale: loc);
        final choose = find.byWidgetPredicate(
          (w) => w is Text && (w.data == 'Choose' || w.data == 'اختار'),
        );
        if (choose.evaluate().isNotEmpty) {
          await tester.tap(choose.first);
          await tester.pumpAndSettle();
        }
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('|');
        for (final n in const ['restaurant', 'receipt_long', 'shopping_cart']) {
          expect(texts, isNot(contains(n)));
        }
      },
    );
  }

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

  testWidgets('FU-158c: edit cannot change the currency', (tester) async {
    await pumpEditor(tester, FakeEditor(), existing: txnRec('a', minor: 45000));
    await tester.tap(find.text('EGP'));
    await tester.pumpAndSettle();
    expect(find.text('Currency'), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
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

  testWidgets('prefill account (receipt last-4) is kept, not the default', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(
      tester,
      ed,
      prefill: TxnPrefill(
        type: TxnEditType.expense,
        amountText: '450.00',
        currency: Currency.of('USD'),
        accountId: 'acc2',
      ),
    );
    expect(find.textContaining('Wallet'), findsWidgets);
    await chooseCategory(tester, 'Food');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ed.added.single.single.accountId, 'acc2');
  });

  testWidgets('prefill account: a saved transaction there opens the dialog', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpEditor(
      tester,
      ed,
      repo: FakeRepo([
        txnRec('dup', account: 'acc2', currency: Currency.of('USD')),
      ]),
      prefill: TxnPrefill(
        type: TxnEditType.expense,
        amountText: '450.00',
        currency: Currency.of('USD'),
        accountId: 'acc2',
        checkDuplicate: true,
      ),
    );
    await chooseCategory(tester, 'Food');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('scan-duplicate-save')), findsOneWidget);
    expect(ed.added, isEmpty);
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
