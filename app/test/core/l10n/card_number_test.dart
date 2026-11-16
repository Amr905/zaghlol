import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/card_number.dart';

void main() {
  test('Arabic-Indic and Western input both render Western digits', () {
    expect(formatCardTail('٥٠٧٥'), '\u2066•••• 5075\u2069');
    expect(formatCardTail('5075'), '\u2066•••• 5075\u2069');
  });

  test('label with and without a last-4', () {
    expect(formatAccountWithCard('CIB', null), 'CIB');
    expect(formatAccountWithCard('CIB', ''), 'CIB');
    expect(formatAccountWithCard('CIB', '١٢٣٤'), 'CIB \u2066•••• 1234\u2069');
  });

  for (final dir in TextDirection.values) {
    testWidgets('renders the same text under $dir', (tester) async {
      await tester.pumpWidget(
        Directionality(textDirection: dir, child: Text(formatCardTail('٥٠٧٥'))),
      );
      expect(find.textContaining('•••• 5075'), findsOneWidget);
    });
  }
}
