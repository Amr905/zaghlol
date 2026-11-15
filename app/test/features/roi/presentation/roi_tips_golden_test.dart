@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'roi_tips_screen_test.dart' as base;

void main() {
  for (final loc in [const Locale('ar', 'EG'), const Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${loc.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('roi tips golden $name', (t) async {
        await base.pump(
          t,
          locale: loc,
          dark: dark,
          tips: {
            'EGP': [
              base.tip(RoiRule.coffeeMachine, base.egp),
              base.tip(RoiRule.idleCash, base.egp),
            ],
          },
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../../goldens/roi_tips_$name.png'),
        );
      });
    }
  }
}
