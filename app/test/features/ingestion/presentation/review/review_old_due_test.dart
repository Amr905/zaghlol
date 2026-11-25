// T-250: the "was a due reminder, remove it?" card in ar and en. Remove and
// Keep only call the action port; nothing is removed by showing the card or
// by a swipe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/ui/z_button.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';

import 'review_harness.dart';

final _card = OldDueCardModel(
  itemId: 'd1',
  txnId: 't1',
  amount: egp(5177),
  occurredAt: DateTime.utc(2026, 11, 20, 8),
);

const _strings = {
  'en': (
    q: 'This was a payment-due reminder, not spending — remove it?',
    remove: 'Remove',
    keep: 'Keep',
    removed: 'Removed from your spending',
  ),
  'ar': (
    q: 'ده كان تذكير بميعاد سداد، مش مصروف — نشيله؟',
    remove: 'شيله',
    keep: 'خليه',
    removed: 'شلناه من مصاريفك',
  ),
};

void main() {
  for (final e in _strings.entries) {
    final lang = e.key;
    final s = e.value;
    group('old due card [$lang]', () {
      testWidgets('shows the question and both buttons; nothing is called '
          'until a tap', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(
            actions: a,
            queue: [_card],
            locale: Locale(lang),
            scale: 1.3,
          ),
        );
        expect(find.text(s.q), findsOneWidget);
        expect(find.widgetWithText(ZButton, s.remove), findsOneWidget);
        expect(find.widgetWithText(ZButton, s.keep), findsOneWidget);
        expect(a.calls, isEmpty);
        expect(t.takeException(), isNull);
      });

      testWidgets('Remove calls remove and offers Undo', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(actions: a, queue: [_card], locale: Locale(lang)),
        );
        await t.tap(find.widgetWithText(ZButton, s.remove));
        await t.pump();
        await t.pump();
        expect(a.calls, ['oldDueRemove:d1']);
        await t.pump(const Duration(milliseconds: 750));
        expect(find.text(s.removed), findsOneWidget);
        await t.tap(find.byType(SnackBarAction));
        await t.pump();
        await t.pump();
        expect(a.calls, ['oldDueRemove:d1', 'oldDueUndo:batch-d1']);
      });

      testWidgets('T-257: Remove on a stale offer shows a neutral message', (
        t,
      ) async {
        final a = FakeActions()..refuseOldDue = true;
        await pumpReview(
          t,
          reviewApp(actions: a, queue: [_card], locale: Locale(lang)),
        );
        await t.tap(find.widgetWithText(ZButton, s.remove));
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 750));
        final l = lookupAppLocalizations(Locale(lang));
        expect(
          find.text(l.ingestionReviewOldDueAlreadyHandled),
          findsOneWidget,
        );
        expect(find.text(l.reviewErrorSaveFailed), findsNothing);
        expect(find.byType(SnackBarAction), findsNothing);
      });

      testWidgets('Keep calls keep only', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(actions: a, queue: [_card], locale: Locale(lang)),
        );
        await t.tap(find.widgetWithText(ZButton, s.keep));
        await t.pump();
        expect(a.calls, ['oldDueKeep:d1']);
      });

      testWidgets('swipe never removes', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(actions: a, queue: [_card], locale: Locale(lang)),
        );
        await t.drag(find.byType(Dismissible), const Offset(300, 0));
        await t.drag(find.byType(Dismissible), const Offset(-300, 0));
        await t.pump();
        expect(a.calls.where((c) => c.startsWith('oldDueRemove')), isEmpty);
      });
    });
  }
}
