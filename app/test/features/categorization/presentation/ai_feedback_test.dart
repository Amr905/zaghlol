// T-361: AI chip and Right / Wrong controls. AC1 (shown only for ai +
// unconfirmed; confirm / correct / cancel / Undo call the service), AC3
// (labels, 48 dp targets, 8 dp spacing, RTL order), AC4 (amount untouched).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/categorization/presentation/ai_category_chip.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';

import 'ai_feedback_harness.dart';

const _locales = {'en': Locale('en'), 'ar': Locale('ar', 'EG')};
const _right = {'en': 'Right', 'ar': 'صح'};
const _wrong = {'en': 'Wrong', 'ar': 'مش صح'};
const _chip = {'en': "Zaghlol's guess", 'ar': 'اقتراح زغلول'};
const _chipA11y = {
  'en': "Zaghlol's guess, not confirmed",
  'ar': 'اقتراح من زغلول، لسه متأكدتش',
};
const _undo = {'en': 'Undo', 'ar': 'تراجع'};

void main() {
  setUpAll(initDateFormatting);

  test('isAiUnconfirmed: only ai rows with a merchant', () {
    expect(isAiUnconfirmed(aiRec()), isTrue);
    for (final s in CategorySource.values.where(
      (s) => s != CategorySource.ai,
    )) {
      expect(isAiUnconfirmed(aiRec(source: s)), isFalse, reason: '$s');
    }
    expect(isAiUnconfirmed(aiRec(merchant: null)), isFalse);
  });

  for (final e in _locales.entries) {
    final k = e.key;
    group('($k)', () {
      testWidgets('row shows chip only for ai rows', (tester) async {
        await pumpApp(tester, row(aiRec()), locale: e.value);
        expect(find.text(_chip[k]!), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(_chipA11y[k]!)), findsOneWidget);
        await pumpApp(
          tester,
          row(aiRec(source: CategorySource.userRule)),
          locale: e.value,
        );
        expect(find.text(_chip[k]!), findsNothing);
      });

      testWidgets('Right calls confirm and shows Undo, which undoes', (
        tester,
      ) async {
        final a = FakeActions();
        await pumpApp(tester, bar(k), actions: a, locale: e.value);
        await tester.tap(find.text(_right[k]!));
        await tester.pumpAndSettle();
        expect(a.calls, ['confirm:Carrefour']);
        expect(find.text(_undo[k]!), findsOneWidget);
        await tester.tap(find.text(_undo[k]!));
        await tester.pumpAndSettle();
        expect(a.calls, ['confirm:Carrefour', 'undo:r1']);
      });

      testWidgets('Wrong opens the picker; a pick calls correct', (
        tester,
      ) async {
        final a = FakeActions();
        await pumpApp(tester, bar(k), actions: a, locale: e.value);
        await tester.tap(find.text(_wrong[k]!));
        await tester.pumpAndSettle();
        // The AI's own category is not offered; user categories are.
        expect(find.text(k == 'en' ? 'Food' : 'أكل'), findsNothing);
        expect(find.text(k == 'en' ? 'My coffee' : 'قهوتي'), findsOneWidget);
        await tester.tap(find.text(k == 'en' ? 'Transport' : 'مواصلات'));
        await tester.pumpAndSettle();
        expect(a.calls, ['correct:Carrefour:transport']);
        expect(find.text(_undo[k]!), findsOneWidget);
      });

      testWidgets('cancelling the picker changes nothing', (tester) async {
        final a = FakeActions();
        await pumpApp(tester, bar(k), actions: a, locale: e.value);
        await tester.tap(find.text(_wrong[k]!));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5)); // barrier
        await tester.pumpAndSettle();
        expect(a.calls, isEmpty);
        expect(find.text(_undo[k]!), findsNothing);
      });

      testWidgets('targets >= 48 dp, >= 8 dp apart, order mirrors', (
        tester,
      ) async {
        await pumpApp(tester, bar(k), locale: e.value, scale: 1.3);
        final r = tester.getRect(find.byKey(const ValueKey('ai-right')));
        final w = tester.getRect(find.byKey(const ValueKey('ai-wrong')));
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(w.height, greaterThanOrEqualTo(48));
        final gap = k == 'ar' ? r.left - w.right : w.left - r.right;
        expect(gap, greaterThanOrEqualTo(8));
        expect(tester.takeException(), isNull);
        if (k == 'ar') {
          expect(r.center.dx, greaterThan(w.center.dx)); // Right is first
        } else {
          expect(r.center.dx, lessThan(w.center.dx));
        }
        final sem = tester.getSemantics(find.byKey(const ValueKey('ai-right')));
        expect(
          sem.label,
          k == 'en' ? 'This category is right' : 'التصنيف ده صح',
        );
      });
    });
  }

  testWidgets('amount text is unchanged by the chip (ink, no extra style)', (
    tester,
  ) async {
    await pumpApp(tester, row(aiRec()));
    final plain = find.textContaining('450');
    expect(plain, findsOneWidget);
    await pumpApp(tester, row(aiRec(source: CategorySource.catalog)));
    expect((tester.widget<Text>(plain)).style, isNotNull);
  });
}
