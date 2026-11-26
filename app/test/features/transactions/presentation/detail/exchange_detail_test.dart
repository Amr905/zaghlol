// T-281: S-12 shows an exchange as one unit (both legs, rate), hides Edit,
// and deletes with the exchange copy and Undo. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/data/transaction_detail_reader.dart';
import 'package:zaghlol/features/transactions/domain/exchange.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/detail/exchange_detail_body.dart';

import '../detail_edit_harness.dart';
import '../list/list_harness.dart';

TxnDetail exchangeDetail() {
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
  return TxnDetail(
    record: out,
    counterpart: inn,
    exchange: TxnExchange(
      pairId: 'p1',
      kind: 'fx_conversion',
      sent: out,
      received: inn,
    ),
  );
}

void main() {
  setUpAll(initDateFormatting);

  for (final (locale, rate, dir) in [
    (const Locale('en'), '1 USD = 49.50 EGP', TextDirection.ltr),
    (const Locale('ar', 'EG'), '١ USD = ٤٩٫٥٠ EGP', TextDirection.rtl),
  ]) {
    testWidgets('one exchange view with both legs and the rate ($locale)', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        Harness(FakeRepo([])),
        id: 'xo',
        detail: AsyncData(exchangeDetail()),
        locale: locale,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ExchangeDetailBody), findsOneWidget);
      expect(find.textContaining(rate), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(ExchangeDetailBody))),
        dir,
      );
    });
  }

  testWidgets('delete asks with the exchange copy, then Undo', (tester) async {
    final h = Harness(FakeRepo([]));
    await pumpDetail(tester, h, id: 'xo', detail: AsyncData(exchangeDetail()));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this exchange?'), findsOneWidget);
    expect(
      find.textContaining('Both sides are deleted together.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(h.actions.calls, ['delete:1']);
    expect(find.text('Exchange deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(h.actions.calls, ['delete:1', 'undo:batch1']);
  });
}
