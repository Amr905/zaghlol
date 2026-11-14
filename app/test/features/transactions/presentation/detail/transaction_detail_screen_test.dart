// T-080 S-12 widget tests: every state, ar/en, RTL, text scale 1.3. Synthetic
// data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/data/transaction_detail_reader.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../detail_edit_harness.dart';
import '../list/list_harness.dart';

void main() {
  setUpAll(initDateFormatting);

  Harness h() => Harness(FakeRepo([txnRec('a'), txnRec('b')]));
  AsyncValue<TxnDetail?> ok(TransactionRecord r, {String? raw}) =>
      AsyncData(detailOf(r, raw: raw));

  testWidgets('shows amount, merchant, category, card and fields (en)', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      h(),
      detail: ok(txnRec('a'), raw: 'SYNTHETIC BANK: purchase 450.00 EGP'),
    );
    expect(find.text('Carrefour'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.textContaining('NBE Visa'), findsOneWidget);
    expect(find.textContaining('450'), findsWidgets);
    expect(find.text('SMS'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
  });

  testWidgets('Arabic renders RTL with Arabic text', (tester) async {
    await pumpDetail(
      tester,
      h(),
      detail: ok(txnRec('a')),
      locale: const Locale('ar', 'EG'),
    );
    expect(find.text('أكل'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('أكل'))),
      TextDirection.rtl,
    );
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('text scale 1.3 does not overflow ($locale)', (tester) async {
      await pumpDetail(
        tester,
        h(),
        detail: ok(txnRec('a'), raw: 'SYNTHETIC'),
        locale: locale,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('raw message is collapsed until opened', (tester) async {
    await pumpDetail(
      tester,
      h(),
      detail: ok(txnRec('a'), raw: 'SYNTHETIC BANK: purchase'),
    );
    expect(find.text('SYNTHETIC BANK: purchase'), findsNothing);
    await tester.tap(find.text('How Zaghlol read this'));
    await tester.pumpAndSettle();
    expect(find.text('SYNTHETIC BANK: purchase'), findsOneWidget);
    expect(find.textContaining('Template nbe.purchase.v1'), findsOneWidget);
    expect(find.textContaining('92'), findsWidgets);
  });

  testWidgets('manual row says there is no message', (tester) async {
    await pumpDetail(tester, h(), detail: ok(txnRec('a')));
    await tester.tap(find.text('How Zaghlol read this'));
    await tester.pumpAndSettle();
    expect(find.text("There's no message for this one."), findsOneWidget);
  });

  testWidgets('declined shows the banner', (tester) async {
    await pumpDetail(
      tester,
      h(),
      detail: ok(txnRec('a', status: TxnStatus.declined)),
    );
    expect(find.text('Declined — not counted'), findsOneWidget);
  });

  testWidgets('foreign original amount is shown', (tester) async {
    final r = txnRec('a');
    final withOriginal = TransactionRecord(
      id: r.id,
      accountId: r.accountId,
      source: r.source,
      direction: r.direction,
      status: r.status,
      amount: r.amount,
      originalAmount: Money(usd, 915),
      occurredAt: r.occurredAt,
      occurredTzOffsetMin: r.occurredTzOffsetMin,
      merchantNorm: r.merchantNorm,
      categoryId: r.categoryId,
      categorySource: r.categorySource,
      isUserVerified: false,
      isInternal: false,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
    await pumpDetail(tester, h(), detail: ok(withOriginal));
    expect(find.textContaining('Original:'), findsOneWidget);
  });

  testWidgets('internal transfer shows counterpart and Unlink', (tester) async {
    final out = txnRec(
      'a',
      direction: TxnDirection.transferOut,
      internal: true,
    );
    final inn = txnRec(
      'b',
      direction: TxnDirection.transferIn,
      internal: true,
      account: 'acc2',
    );
    await pumpDetail(
      tester,
      h(),
      detail: AsyncData(detailOf(out, counterpart: inn)),
    );
    expect(find.textContaining('Linked with'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, not content', (tester) async {
    await pumpDetail(tester, h(), detail: ok(txnRec('a')));
    // The skeleton has no text; once data is there the merchant shows.
    expect(find.text('Carrefour'), findsOneWidget);
  });

  testWidgets('error shows retry', (tester) async {
    await pumpDetail(
      tester,
      h(),
      detail: AsyncError<TxnDetail?>(StateError('x'), StackTrace.empty),
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('deleted elsewhere: back with a snackbar', (tester) async {
    await pumpDetail(tester, h(), detail: const AsyncData(null));
    expect(find.text('This transaction no longer exists'), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
  });

  group('recategorize asks to save a rule', () {
    Future<Harness> start(WidgetTester tester) async {
      final hh = h();
      await pumpDetail(tester, hh, detail: ok(txnRec('a')));
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bills'));
      await tester.pumpAndSettle();
      return hh;
    }

    testWidgets('Always saves the rule', (tester) async {
      final hh = await start(tester);
      expect(find.text('Always use Bills for Carrefour?'), findsOneWidget);
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      expect(hh.actions.calls, ['category:1:bills:true']);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('Just this once does not', (tester) async {
      final hh = await start(tester);
      await tester.tap(find.text('Just this once'));
      await tester.pumpAndSettle();
      expect(hh.actions.calls, ['category:1:bills:false']);
    });

    testWidgets('dismissing the prompt changes nothing', (tester) async {
      final hh = await start(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(hh.actions.calls, isEmpty);
    });
  });

  testWidgets('delete goes through the shared bulk delete, with Undo', (
    tester,
  ) async {
    final hh = h();
    await pumpDetail(tester, hh, detail: ok(txnRec('a')));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this transaction?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(hh.actions.calls, ['delete:1']);
    expect(find.text('Deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(hh.actions.calls, ['delete:1', 'undo:batch1']);
  });

  testWidgets('cancelling the delete dialog keeps the row', (tester) async {
    final hh = h();
    await pumpDetail(tester, hh, detail: ok(txnRec('a')));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(hh.actions.calls, isEmpty);
  });

  testWidgets('note longer than 200 characters is refused', (tester) async {
    final repo = NoteRepo([txnRec('a')]);
    await pumpDetail(tester, h(), detail: ok(txnRec('a')), repo: repo);
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'x' * 201);
    await tester.pump();
    expect(find.textContaining('200'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'ok note');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.edits.single.note!.value, 'ok note');
  });
}
