import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';
import 'package:zaghlol/core/ui/z_button.dart';

import 'review_harness.dart';

ReviewTransferOption cand(String id, int minor) => ReviewTransferOption(
  txnId: id,
  amount: egp(minor),
  accountLabel: 'Cafe $id',
  occurredAt: DateTime(2026, 11, 1),
);

SuggestionCardModel card(List<ReviewTransferOption> c) => SuggestionCardModel(
  itemId: 'p1',
  kind: 'reimbursement_suggestion',
  ambiguousRefund: false,
  amount: egp(5000),
  isIncome: true,
  candidates: c,
);

void main() {
  for (final lang in ['en', 'ar']) {
    group('pair suggestion [$lang]', () {
      testWidgets('2 candidates: no link until the user taps one', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(
            actions: a,
            queue: [
              card([cand('e1', 3000), cand('e2', 2000)]),
            ],
            locale: Locale(lang),
            scale: 1.3,
          ),
        );
        expect(find.byType(RadioListTile<int>), findsNWidgets(2));
        // Confirm is disabled; swipe-accept is not offered.
        final confirm = find.widgetWithText(
          ZButton,
          lang == 'en' ? 'Confirm' : 'تأكيد',
        );
        expect(
          confirm.evaluate().isEmpty ||
              t.widget<ZButton>(confirm).onPressed == null,
          isTrue,
        );
        await t.drag(
          find.byType(Dismissible),
          Offset(lang == 'en' ? 300 : -300, 0),
        );
        await t.pumpAndSettle();
        expect(a.calls, isEmpty);
        await t.tap(find.byType(RadioListTile<int>).last);
        await t.pump();
        await t.tap(find.byType(ZButton).first);
        await t.pump();
        expect(a.calls, ['acceptCand:p1:e2']);
      });

      testWidgets('1 candidate: shown, one tap links it', (t) async {
        final a = FakeActions();
        await pumpReview(
          t,
          reviewApp(
            actions: a,
            queue: [
              card([cand('e1', 3000)]),
            ],
            locale: Locale(lang),
          ),
        );
        expect(find.byType(RadioListTile<int>), findsOneWidget);
        await t.tap(find.byType(ZButton).first);
        await t.pump();
        expect(a.calls, ['acceptCand:p1:e1']);
      });
    });
  }
}
