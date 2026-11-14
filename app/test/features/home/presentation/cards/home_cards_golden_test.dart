@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/golden_matrix.dart';
import 'cards_harness.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('home cards golden ${v.name}', (tester) async {
      await pumpCards(
        tester,
        locale: v.locale,
        dark: v.dark,
        cards: allCards,
        actions: FakeCardActions(),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_cards_${v.name}.png'),
      );
    });
  }
}
