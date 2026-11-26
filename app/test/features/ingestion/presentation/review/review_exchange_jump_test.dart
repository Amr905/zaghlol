// T-272: the "Did you exchange money?" card in ar and en. Showing it calls
// nothing; No dismisses (deferred, with undo like other dismissals); Yes
// opens the exchange entry (nothing is saved without that screen's Save).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_button.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';

import 'review_harness.dart';

final _card = ExchangeJumpCardModel(
  itemId: 'j1',
  accountId: 'acc1',
  amount: egp(2970000),
  asOf: DateTime.utc(2026, 11, 26, 8),
);

const _strings = {
  'en': (q: 'Your EGP balance rose by about', yes: 'Yes, record it', no: 'No'),
  'ar': (q: 'غيّرت عملة؟', yes: 'أيوه، سجلها', no: 'لأ'),
};

void main() {
  for (final e in _strings.entries) {
    final s = e.value;
    testWidgets('[${e.key}] question with the rise, both buttons, no call '
        'until a tap', (t) async {
      final a = FakeActions();
      await pumpReview(
        t,
        reviewApp(
          actions: a,
          queue: [_card],
          locale: Locale(e.key),
          scale: 1.3,
        ),
      );
      expect(find.textContaining(s.q), findsOneWidget);
      expect(find.widgetWithText(ZButton, s.yes), findsOneWidget);
      expect(find.widgetWithText(ZButton, s.no), findsOneWidget);
      expect(a.calls, isEmpty);
      expect(t.takeException(), isNull);
    });
  }
}
