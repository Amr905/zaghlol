import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/onboarding/application/contextual.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';

import 'cards_harness.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

void main() {
  for (final locale in [_ar, _en]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('all cards, no overflow (${locale.languageCode} x$scale)', (
        tester,
      ) async {
        await pumpCards(
          tester,
          locale: locale,
          cards: allCards,
          actions: FakeCardActions(),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-card-suggestion')), findsOne);
        expect(find.byKey(const ValueKey('home-card-app-lock')), findsOne);
        expect(find.byKey(const ValueKey('home-card-finish-setup')), findsOne);
        final dir = Directionality.of(
          tester.element(find.byKey(const ValueKey('home-card-app-lock'))),
        );
        expect(
          dir,
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }

  testWidgets('empty model renders nothing', (tester) async {
    await pumpCards(
      tester,
      locale: _en,
      cards: const HomeCards(),
      actions: FakeCardActions(),
    );
    expect(find.byKey(const ValueKey('home-card-suggestion')), findsNothing);
    expect(find.byKey(const ValueKey('home-card-app-lock')), findsNothing);
  });

  testWidgets('payday card quotes the salary and accepts the day', (
    tester,
  ) async {
    final a = FakeCardActions();
    await pumpCards(
      tester,
      locale: _en,
      cards: HomeCards(
        suggestion: const SetupSuggestion(
          SetupSuggestionKind.payday,
          paydayDay: 25,
        ),
        salary: salary,
      ),
      actions: a,
    );
    expect(find.textContaining('32,000'), findsOneWidget);
    await tester.tap(find.text('Yes, day 25'));
    await tester.pump();
    expect(a.calls, ['payday:25']);
  });

  testWidgets('budget card: yes opens set budget, no only dismisses', (
    tester,
  ) async {
    final a = FakeCardActions();
    var opened = 0;
    await pumpCards(
      tester,
      locale: _en,
      cards: const HomeCards(
        suggestion: SetupSuggestion(SetupSuggestionKind.budget),
      ),
      actions: a,
      openSetBudget: () => opened++,
    );
    await tester.tap(find.byKey(const ValueKey('suggestion-no')));
    await tester.pump();
    expect(a.calls, ['handle:budget']);
    expect(opened, 0);
    await tester.tap(find.byKey(const ValueKey('suggestion-yes')));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('backup card: yes opens backup', (tester) async {
    var opened = 0;
    await pumpCards(
      tester,
      locale: _ar,
      cards: const HomeCards(
        suggestion: SetupSuggestion(SetupSuggestionKind.backup),
      ),
      actions: FakeCardActions(),
      openBackup: () => opened++,
    );
    await tester.tap(find.byKey(const ValueKey('suggestion-yes')));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('app lock toggle enables, failure shows the message', (
    tester,
  ) async {
    final a = FakeCardActions()..lockResult = EnableLockResult.notSecure;
    await pumpCards(
      tester,
      locale: _en,
      cards: const HomeCards(offerAppLock: true),
      actions: a,
    );
    await tester.tap(find.byKey(const ValueKey('app-lock-switch')));
    await tester.pump();
    await tester.pump();
    expect(a.calls, ['lock']);
    expect(find.byKey(const ValueKey('app-lock-error')), findsOneWidget);
  });

  testWidgets('finish setup card shows the count and opens', (tester) async {
    var opened = 0;
    await pumpCards(
      tester,
      locale: _en,
      cards: const HomeCards(stepsLeft: 2),
      actions: FakeCardActions(),
      openFinishSetup: () => opened++,
    );
    expect(find.textContaining('2 steps left'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-card-finish-setup')));
    expect(opened, 1);
  });

  testWidgets('semantics: lock switch labelled, 48dp targets', (tester) async {
    await pumpCards(
      tester,
      locale: _en,
      cards: const HomeCards(offerAppLock: true, stepsLeft: 1),
      actions: FakeCardActions(),
    );
    expect(
      find.bySemanticsLabel(RegExp('Lock Zaghlol with your phone lock')),
      findsWidgets,
    );
    final h = tester.getSize(
      find.byKey(const ValueKey('home-card-finish-setup')),
    );
    expect(h.height, greaterThanOrEqualTo(48));
  });
}
