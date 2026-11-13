// T-079: S-11 widget tests, one per state, in ar and en, with the 1.3 text
// scale. Acceptance criteria are named in the test titles. All data synthetic.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/ui/z_components.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/transactions_list_screen.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';

import 'list_harness.dart';

const _ar = Locale('ar', 'EG');

Harness tenRows() => Harness(
  FakeRepo([
    for (var i = 0; i < 10; i++)
      txnRec('t$i', merchant: 'Shop$i', minor: 1000 + i, daysAgo: i % 2),
  ]),
);

void main() {
  setUpAll(initDateFormatting);

  for (final (name, locale) in [('en', const Locale('en')), ('ar', _ar)]) {
    group('list ($name)', () {
      testWidgets('rows, day headers and ink-coloured spending', (
        tester,
      ) async {
        final h = Harness(
          FakeRepo([
            txnRec('a', merchant: 'Carrefour', minor: 45000),
            txnRec('b', merchant: 'Talabat', minor: 28500),
            txnRec(
              'c',
              merchant: 'Salary',
              minor: 900000,
              direction: TxnDirection.income,
              daysAgo: 1,
            ),
          ]),
        );
        await pumpList(tester, h, locale: locale);
        expect(find.text('Carrefour'), findsOneWidget);
        expect(find.text('Talabat'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Two day headers (today, yesterday), each with a total.
        expect(find.byType(TxnDayHeader), findsNWidgets(2));
        // Spending text uses the ink colour, not red.
        final money = tester.widget<ZMoneyText>(find.byType(ZMoneyText).at(2));
        expect(money.kind, ZMoneyKind.expense);
      });

      testWidgets('RTL/LTR direction and text scale 1.3 do not overflow', (
        tester,
      ) async {
        await pumpList(tester, tenRows(), locale: locale, textScale: 1.3);
        expect(tester.takeException(), isNull);
        await tester.longPress(find.byType(TxnRow).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final rtl = Directionality.of(tester.element(find.byType(Scaffold)));
        expect(rtl, name == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      });

      testWidgets('loading shows skeleton rows', (tester) async {
        final h = tenRows();
        h.repo.gate = Completer<void>();
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpListNoSettle(tester, h, locale);
        expect(find.byType(TxnRow), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        h.repo.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(TxnRow), findsWidgets);
      });

      testWidgets('empty (no data) offers Add expense', (tester) async {
        await pumpList(tester, Harness(FakeRepo([])), locale: locale);
        expect(find.byType(TxnRow), findsNothing);
        expect(find.byType(ZButton), findsOneWidget);
      });

      testWidgets('error shows a banner with Try again', (tester) async {
        final h = tenRows()..repo.failWith = StateError('x');
        await pumpList(tester, h, locale: locale);
        expect(find.byType(ZBanner), findsOneWidget);
        h.repo.failWith = null;
        await tester.tap(find.text(locale == _ar ? 'جرّب تاني' : 'Try again'));
        await tester.pumpAndSettle();
        expect(find.byType(TxnRow), findsWidgets);
      });
    });
  }

  testWidgets('AC2 no results names the search; Clear brings rows back', (
    tester,
  ) async {
    final h = tenRows();
    await pumpList(tester, h);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(txnSearchDebounce);
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches "zzz"'), findsOneWidget);
    await tester.tap(find.text('Clear search & filters'));
    await tester.pumpAndSettle();
    expect(find.byType(TxnRow), findsWidgets);
  });

  testWidgets('AC2 no results names the search (ar)', (tester) async {
    await pumpList(tester, tenRows(), locale: _ar);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(txnSearchDebounce);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('zzz'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('search is debounced 250 ms', (tester) async {
    final h = tenRows();
    await pumpList(tester, h);
    final base = h.repo.queries;
    await tester.enterText(find.byType(TextField), 'Sh');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.repo.queries, base);
    await tester.enterText(find.byType(TextField), 'Shop1');
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.repo.queries, base);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(h.repo.texts.last, 'Shop1');
    expect(h.repo.queries, base + 1);
  });

  testWidgets('type filter chip narrows the list', (tester) async {
    final h = Harness(
      FakeRepo([
        txnRec('a', merchant: 'Carrefour'),
        txnRec('b', merchant: 'Salary', direction: TxnDirection.income),
      ]),
    );
    await pumpList(tester, h);
    await tester.ensureVisible(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Carrefour'), findsNothing);
  });

  group('selection mode', () {
    testWidgets('AC1 select 10, change category, undo restores all', (
      tester,
    ) async {
      final h = tenRows();
      await pumpList(tester, h);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('10 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bulk-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();

      expect(h.actions.calls.single, 'category:10:bills:false');
      expect(h.repo.rows.every((t) => t.categoryId == 'bills'), isTrue);
      expect(find.text('10 transactions updated'), findsOneWidget);
      expect(find.text('10 selected'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.actions.calls.last, 'undo:batch1');
      expect(h.repo.rows.every((t) => t.categoryId == 'food'), isTrue);
    });

    testWidgets('long-press enters selection with that row ticked; title '
        'uses locale digits (ar)', (tester) async {
      await pumpList(tester, tenRows(), locale: _ar);
      await tester.longPress(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      expect(find.text('اخترت ١'), findsOneWidget);
      await tester.tap(find.byType(TxnRow).at(1));
      await tester.pumpAndSettle();
      expect(find.text('اخترت ٢'), findsOneWidget);
    });

    testWidgets('the always-use switch is passed to the bulk edit', (
      tester,
    ) async {
      final h = tenRows();
      await pumpList(tester, h);
      await tester.longPress(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      expect(h.actions.calls.single, 'category:1:bills:true');
    });

    testWidgets('bulk delete asks first; Cancel deletes nothing, Delete does, '
        'Undo brings rows back', (tester) async {
      final h = tenRows();
      await pumpList(tester, h);
      await tester.longPress(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TxnRow).at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bulk-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 transactions?'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(h.actions.calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('bulk-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(h.actions.calls.single, 'delete:2');
      expect(h.repo.rows.length, 8);
      expect(find.text('2 transactions deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.repo.rows.length, 10);
    });

    testWidgets('cancel leaves selection mode; action buttons keep a 48 dp '
        'target', (tester) async {
      await pumpList(tester, tenRows());
      await tester.longPress(find.byType(TxnRow).first);
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(const ValueKey('bulk-category')));
      expect(size.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const ValueKey('bulk-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
    });
  });

  group('day totals', () {
    test('per currency, internal and declined rows are left out', () {
      final totals = dayTotals([
        txnRec('a', minor: 45000),
        txnRec('b', minor: 28500),
        txnRec('u', minor: 900, currency: usd),
        txnRec('i', minor: 99999, internal: true),
        txnRec('d', minor: 77777, status: TxnStatus.declined),
        txnRec('s', minor: 10000, direction: TxnDirection.income),
      ]);
      final byCode = {for (final m in totals) m.currency.code: m.minor};
      expect(byCode, {'EGP': -63500, 'USD': -900});
    });
  });
}

Future<void> pumpListNoSettle(
  WidgetTester tester,
  Harness h,
  Locale locale,
) async {
  await tester.pumpWidget(listApp(h, locale: locale));
  await tester.pump();
}
