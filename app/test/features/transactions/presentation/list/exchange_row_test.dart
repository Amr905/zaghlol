// T-281: an exchange is one row in S-11, in ar and en and under a currency
// filter; the day header does not count it. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/exchange.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/transactions_list_screen.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_exchange_row.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';

import 'list_harness.dart';

const _ar = Locale('ar', 'EG');

/// USD 600.00 given, EGP 29,700.00 got: bank rate 49.50.
Harness exchangeHarness() {
  final out = txnRec(
    'xo',
    merchant: '',
    minor: 60000,
    currency: usd,
    direction: TxnDirection.transferOut,
    internal: true,
    account: 'acc2',
    categoryId: null,
  );
  final inn = txnRec(
    'xi',
    merchant: '',
    minor: 2970000,
    direction: TxnDirection.transferIn,
    internal: true,
    categoryId: null,
  );
  final x = TxnExchange(
    pairId: 'p1',
    kind: 'cross_currency',
    sent: out,
    received: inn,
  );
  return Harness(
    FakeRepo([out, inn, txnRec('a', merchant: 'Carrefour', minor: 45000)]),
  )..exchanges = {'xo': x, 'xi': x};
}

void main() {
  setUpAll(initDateFormatting);

  for (final (name, locale) in [('en', const Locale('en')), ('ar', _ar)]) {
    testWidgets('one row per exchange with the bank rate ($name)', (
      tester,
    ) async {
      await pumpList(tester, exchangeHarness(), locale: locale);
      expect(tester.takeException(), isNull);
      expect(find.byType(TxnExchangeRow), findsOneWidget);
      // Only the ordinary expense is a TxnRow; neither leg is.
      expect(find.byType(TxnRow), findsOneWidget);
      final rateLine = name == 'en'
          ? 'Bank rate 49.50 · not spending'
          : 'سعر البنك ٤٩٫٥٠ · مش مصروف';
      expect(find.text(rateLine), findsOneWidget);
      final title = find.textContaining(name == 'en' ? 'Exchanged' : 'غيّرت');
      expect(title, findsOneWidget);
      final text = tester.widget<Text>(title).data!;
      // The arrow points from what was given to what was got; mirrored by
      // the text itself, never by layout.
      expect(text, contains(name == 'en' ? '→' : '←'));
      final arrow = text.indexOf(name == 'en' ? '→' : '←');
      expect(text.indexOf('USD'), lessThan(arrow), reason: 'given first');
      // The day header counts the expense only (the exchange is internal).
      final header = tester.widget<TxnDayHeader>(find.byType(TxnDayHeader));
      expect(header.totals.single.currency.code, 'EGP');
      expect(header.totals.single.minor, -45000);
    });

    testWidgets('a USD filter still shows the exchange row ($name)', (
      tester,
    ) async {
      final h = exchangeHarness();
      await pumpList(tester, h, locale: locale);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsListScreen)),
      );
      container
          .read(txnListFilterProvider.notifier)
          .set(const TxnListFilter().copyWith(currency: usd));
      await tester.pumpAndSettle();
      expect(find.byType(TxnExchangeRow), findsOneWidget);
      expect(find.byType(TxnRow), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping the exchange row opens one leg (the detail shows the '
      'exchange)', (tester) async {
    final opened = <String>[];
    final h = exchangeHarness();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(listApp(h, onOpen: opened.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TxnExchangeRow));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(['xo', 'xi'], contains(opened.single));
  });

  test('collapseExchangeLegs keeps the first leg of each exchange', () {
    final h = exchangeHarness();
    final rows = collapseExchangeLegs(h.repo.rows, h.exchanges);
    expect([for (final r in rows) r.id], ['xo', 'a']);
  });
}
