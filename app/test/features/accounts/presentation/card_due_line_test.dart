// T-245: the card detail's due line from a bank notice, in en and ar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol/features/recurring/data/card_dues_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'card_detail_test.dart' show detailOverrides, pumpDetail;

CardDue due({int paid = 0, int? min = 3000}) => CardDue(
  currency: 'EGP',
  noticeAtMs: 1,
  amountDueMinor: 10000,
  minDueMinor: min,
  dueDate: CivilDate(2026, 11, 25),
  paidMinor: paid,
);

void main() {
  Future<void> show(
    WidgetTester t,
    CardDue? d, {
    Locale locale = const Locale('en'),
    bool dark = false,
  }) => pumpDetail(
    t,
    locale: locale,
    dark: dark,
    overrides: [
      ...detailOverrides(),
      cardDueProvider.overrideWith((ref, id) async => d),
    ],
  );

  testWidgets('en: amount, minimum and date', (t) async {
    await show(t, due());
    expect(find.textContaining('Due '), findsWidgets);
    expect(find.textContaining('min '), findsOneWidget);
    expect(find.textContaining('Nov 25, 2026'), findsOneWidget);
    // The notice replaces the recurring-item line.
    expect(find.text('Statement due Nov 15, 2026'), findsNothing);
  });

  testWidgets('en dark: the same line', (t) async {
    await show(t, due(), dark: true);
    expect(find.textContaining('Nov 25, 2026'), findsOneWidget);
  });

  testWidgets('ar: Egyptian copy with the date', (t) async {
    await show(t, due(), locale: const Locale('ar'));
    expect(find.textContaining('عليك'), findsOneWidget);
    expect(find.textContaining('الأدنى'), findsOneWidget);
  });

  testWidgets('ar dark: the same line', (t) async {
    await show(t, due(), locale: const Locale('ar'), dark: true);
    expect(find.textContaining('عليك'), findsOneWidget);
  });

  testWidgets('a partial payment shows the rest of the minimum', (t) async {
    await show(t, due(paid: 1000));
    expect(find.textContaining('Still to pay'), findsOneWidget);
  });

  testWidgets('paid says so', (t) async {
    await show(t, due(paid: 3000));
    expect(find.text('This statement is paid'), findsOneWidget);
  });

  testWidgets('T-249: zero total and minimum says paid, never "Due EGP 0"', (
    t,
  ) async {
    await show(
      t,
      CardDue(
        currency: 'EGP',
        noticeAtMs: 1,
        amountDueMinor: 0,
        minDueMinor: 0,
        dueDate: CivilDate(2026, 11, 25),
      ),
    );
    expect(find.text('This statement is paid'), findsOneWidget);
    expect(find.textContaining('Due EGP'), findsNothing);
    expect(find.textContaining('min '), findsNothing);
  });

  testWidgets('no notice keeps the old due line', (t) async {
    await show(t, null);
    expect(find.text('Statement due Nov 15, 2026'), findsOneWidget);
  });
}
