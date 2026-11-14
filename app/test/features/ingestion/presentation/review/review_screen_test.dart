import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_harness.dart';

void main() {
  for (final lang in ['en', 'ar']) {
    final locale = Locale(lang);
    group('review screen [$lang] at 1.3x', () {
      testWidgets('shows every card kind without overflow', (tester) async {
        await pumpReview(
          tester,
          reviewApp(
            actions: FakeActions(),
            queue: sampleCards,
            locale: locale,
            scale: 1.3,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Dismissible), findsNWidgets(sampleCards.length));
      });

      testWidgets('empty state', (tester) async {
        await pumpReview(
          tester,
          reviewApp(actions: FakeActions(), queue: [], locale: locale),
        );
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        expect(find.byType(Dismissible), findsNothing);
      });

      testWidgets('error state offers retry', (tester) async {
        await pumpReview(
          tester,
          reviewApp(
            actions: FakeActions(),
            error: StateError('x'),
            locale: locale,
          ),
        );
        expect(find.byType(Dismissible), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(InkWell), findsWidgets);
      });

      testWidgets('loading state shows skeleton', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          reviewApp(actions: FakeActions(), locale: locale),
        );
        await tester.pump();
        expect(find.byType(Dismissible), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(ListView), findsOneWidget);
      });
    });
  }

  group('actions (en)', () {
    testWidgets('category chip applies after the snackbar closes', (
      tester,
    ) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.tap(find.text('Rent'));
      await tester.pump();
      expect(find.text('Filed under Rent'), findsOneWidget);
      expect(actions.calls, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(actions.calls, ['categorize:r1:c1']);
    });

    testWidgets('Undo cancels the pending action', (tester) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.tap(find.text('Food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty);
    });

    testWidgets('confirm on a guess accepts the item', (tester) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.tap(find.text('Confirm').first);
      await tester.pump();
      expect(actions.calls, ['accept:r2']);
    });

    testWidgets('transfer needs a choice, then links', (tester) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      final confirm = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is RadioListTile<int> && w.value == -1,
        ),
        matching: find.byType(Text),
      );
      expect(confirm, findsOneWidget);
      await tester.tap(find.text('Not my transfer'));
      await tester.pump();
      await tester.tap(find.text('Confirm').at(1));
      await tester.pump();
      expect(actions.calls, ['transfer:r4:null']);
    });

    testWidgets('subscription confirm goes to the recurring port', (
      tester,
    ) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.ensureVisible(find.text('Confirm').last);
      await tester.tap(find.text('Confirm').last);
      await tester.pump();
      expect(actions.calls, ['subConfirm:rec1']);
    });

    testWidgets('ambiguous refund can only be dismissed', (tester) async {
      await pumpReview(
        tester,
        reviewApp(actions: FakeActions(), queue: [sampleCards.last]),
      );
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('filter keeps only transfers', (tester) async {
      await pumpReview(
        tester,
        reviewApp(actions: FakeActions(), queue: sampleCards),
      );
      await tester.scrollUntilVisible(
        find.text('Transfers'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfers'));
      await tester.pump();
      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('request bank validates and sends opt-in name only', (
      tester,
    ) async {
      final actions = FakeActions();
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.tap(find.text('Ask us to support this bank').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('never the message itself'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'X');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(find.textContaining('2'), findsWidgets);
      expect(actions.calls, isEmpty);
      await tester.enterText(find.byType(TextField).first, 'XYZ BANK');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['bank:r2:XYZ BANK:EG:sms']);
    });

    testWidgets('request bank failure keeps the form with a message', (
      tester,
    ) async {
      final actions = FakeActions()..failWith = StateError('offline');
      await pumpReview(tester, reviewApp(actions: actions, queue: sampleCards));
      await tester.tap(find.text('Ask us to support this bank').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kept it'), findsOneWidget);
    });

    testWidgets('raw message text is never shown', (tester) async {
      await pumpReview(
        tester,
        reviewApp(actions: FakeActions(), queue: sampleCards),
      );
      expect(find.textContaining('Your balance'), findsNothing);
    });
  });
}
