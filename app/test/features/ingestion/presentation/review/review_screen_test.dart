import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_screen.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';

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

    group('SMS-AUTO original message text', () {
      const body =
          'Your Credit Card ending with * 5075 has been used for USD 114.00';
      final withText = MessageCardModel(
        itemId: 'o1',
        sender: 'HSBC',
        isNewSender: false,
        amount: egp(11400),
        rawMessageId: 'rawO',
        originalText: body,
      );

      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('collapsed by default, shows the text on tap '
            '(${locale.languageCode}, text scale 1.3)', (tester) async {
          await pumpReview(
            tester,
            reviewApp(
              actions: FakeActions(),
              queue: [withText],
              locale: locale,
            ),
          );
          // The body widget is built only when the tile is expanded.
          expect(
            find.byKey(const ValueKey('reviewOriginalBody')),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('reviewOriginalText')));
          await tester.pumpAndSettle();
          expect(find.text(body), findsOneWidget);
        });
      }

      testWidgets('no text, no tile', (tester) async {
        await pumpReview(
          tester,
          reviewApp(
            actions: FakeActions(),
            queue: [
              MessageCardModel(
                itemId: 'o2',
                sender: 'HSBC',
                isNewSender: false,
                amount: egp(100),
              ),
            ],
          ),
        );
        expect(find.byKey(const ValueKey('reviewOriginalText')), findsNothing);
      });
    });

    group('SMS-fuzzy generic suggestions', () {
      final oneTap = MessageCardModel(
        itemId: 'g1',
        sender: 'HSBC',
        isNewSender: false,
        amount: egp(84550),
        merchant: 'Spinneys',
        last4: '6612',
        rawMessageId: 'raw1',
        oneTap: true,
        direction: TxnDirection.expense,
        occurredAt: DateTime.utc(2026, 11, 5, 10),
        bankLabel: 'HSBC Egypt',
      );
      final oneTapTransfer = MessageCardModel(
        itemId: 'g3',
        sender: 'HSBC',
        isNewSender: false,
        amount: egp(200000),
        merchant: 'Ahmed',
        rawMessageId: 'raw3',
        oneTap: true,
        direction: TxnDirection.transferOut,
        occurredAt: DateTime.utc(2026, 11, 5, 10),
        bankLabel: 'HSBC Egypt',
      );
      final partial = MessageCardModel(
        itemId: 'g2',
        sender: 'HSBC',
        isNewSender: false,
        amount: egp(1000),
        rawMessageId: 'raw2',
      );

      // REVIEW-KEEP (PO 2026-11-16).
      final keepable = MessageCardModel(
        itemId: 'k1',
        sender: 'HSBC',
        isNewSender: false,
        amount: egp(5000),
        rawMessageId: 'rawK',
        direction: TxnDirection.expense,
        occurredAt: DateTime.utc(2026, 11, 5, 10),
        bankLabel: 'HSBC Egypt',
        keepable: true,
        institutionCode: 'hsbc',
      );
      final noAmount = MessageCardModel(
        itemId: 'k2',
        sender: 'HSBC',
        isNewSender: false,
        rawMessageId: 'rawK2',
      );
      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('Keep saves as shown in one tap, Edit and Ignore stay '
            '(${locale.languageCode}, text scale 1.3)', (tester) async {
          final actions = FakeActions();
          await pumpReview(
            tester,
            reviewApp(
              actions: actions,
              queue: [keepable],
              locale: locale,
              scale: 1.3,
            ),
          );
          final l = AppLocalizations.of(
            tester.element(find.byType(ReviewScreen)),
          );
          expect(find.text(l.ingestionReviewKeep), findsOneWidget);
          expect(find.text(l.commonActionDismiss), findsOneWidget);
          expect(find.text(l.ingestionReviewUnreadEnter), findsOneWidget);
          expect(find.byKey(const ValueKey('reviewKeepReason')), findsNothing);
          await tester.tap(find.text(l.ingestionReviewKeep));
          await tester.pump();
          expect(actions.calls, ['keep:k1']);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Keep is disabled with a reason when there is no amount '
            '(${locale.languageCode})', (tester) async {
          final actions = FakeActions();
          await pumpReview(
            tester,
            reviewApp(actions: actions, queue: [noAmount], locale: locale),
          );
          final l = AppLocalizations.of(
            tester.element(find.byType(ReviewScreen)),
          );
          await tester.tap(find.text(l.ingestionReviewKeep));
          await tester.pump();
          expect(actions.calls, isEmpty);
          expect(find.text(l.ingestionReviewKeepNoAmount), findsOneWidget);
        });

        testWidgets('original message toggle has its own show / hide labels '
            '(${locale.languageCode})', (tester) async {
          final withText = MessageCardModel(
            itemId: 'k3',
            sender: 'HSBC',
            isNewSender: false,
            amount: egp(100),
            originalText: 'synthetic text',
          );
          await pumpReview(
            tester,
            reviewApp(
              actions: FakeActions(),
              queue: [withText],
              locale: locale,
            ),
          );
          final l = AppLocalizations.of(
            tester.element(find.byType(ReviewScreen)),
          );
          expect(find.text(l.ingestionReviewShowOriginal), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('reviewOriginalText')));
          await tester.pumpAndSettle();
          expect(find.text(l.ingestionReviewHideOriginal), findsOneWidget);
        });
      }

      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets(
          'prefilled guess and one-tap confirm (${locale.languageCode})',
          (tester) async {
            final actions = FakeActions();
            await pumpReview(
              tester,
              reviewApp(actions: actions, queue: [oneTap], locale: locale),
            );
            expect(find.textContaining('Spinneys'), findsOneWidget);
            final l = AppLocalizations.of(
              tester.element(find.byType(ReviewScreen)),
            );
            await tester.tap(find.text(l.commonActionConfirm));
            await tester.pump();
            expect(actions.calls, ['generic:g1']);
            // The learn offer: make a template from this message.
            await tester.pump(const Duration(milliseconds: 800));
            expect(find.text(l.templatesBuilderTitle), findsOneWidget);
            await tester.tap(find.text(l.templatesBuilderTitle));
            await tester.pump();
            expect(actions.calls, ['generic:g1', 'sample:raw1']);
            expect(tester.takeException(), isNull);
          },
        );
      }

      for (final locale in const [Locale('en'), Locale('ar')]) {
        testWidgets('one-tap card shows kind, date and account '
            '(${locale.languageCode})', (tester) async {
          await pumpReview(
            tester,
            reviewApp(
              actions: FakeActions(),
              queue: [oneTap, oneTapTransfer],
              locale: locale,
            ),
          );
          final ctx = tester.element(find.byType(ReviewScreen));
          final l = AppLocalizations.of(ctx);
          final lang = locale.languageCode;
          final digits = ProviderScope.containerOf(ctx)
              .read(digitsModeProvider(lang));
          final details = tester
              .widgetList<Text>(
                find.byKey(const ValueKey('reviewOneTapDetails')),
              )
              .map((t) => t.data!)
              .toList();
          expect(details, hasLength(2));
          final date = ZDateFormat.date(
            DateTime.utc(2026, 11, 5, 10),
            lang,
            digits,
          );
          // Card with last-4: expense, the message date, bank + last-4.
          expect(details[0], contains(l.commonTxnTypeExpense));
          expect(details[0], contains(date));
          expect(details[0], contains('HSBC Egypt'));
          expect(details[0], contains('•••• 6612'));
          // No last-4: transfer, the bank's account.
          expect(details[1], contains(l.commonTxnTypeTransfer));
          expect(details[1], contains(l.commonAccountTypeAccount));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('an incomplete suggestion shows the guess but no confirm', (
        tester,
      ) async {
        final actions = FakeActions();
        await pumpReview(tester, reviewApp(actions: actions, queue: [partial]));
        final l = AppLocalizations.of(
          tester.element(find.byType(ReviewScreen)),
        );
        expect(find.text(l.commonActionConfirm), findsNothing);
        expect(find.text(l.ingestionReviewUnreadEnter), findsOneWidget);
        expect(find.text(l.ingestionReviewGenLowConfidence), findsOneWidget);
      });

      testWidgets('a swipe on an incomplete suggestion saves nothing', (
        tester,
      ) async {
        final actions = FakeActions();
        await pumpReview(tester, reviewApp(actions: actions, queue: [partial]));
        await tester.drag(find.byType(Dismissible), const Offset(500, 0));
        await tester.pumpAndSettle();
        expect(actions.calls, isEmpty);
      });
    });
  });
}
