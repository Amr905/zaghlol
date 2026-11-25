@Tags(['golden'])
library;

// T-247 (D-82): the Home hero without a budget names the cycle after its
// month: the cycle starting 24 Nov is the December one. Clock pinned by the
// model (today 10 Nov 2026). Update with --update-goldens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/golden_matrix.dart';
import 'home_harness.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('home cycle named golden ${v.name}', (tester) async {
      await pumpHome(
        tester,
        locale: v.locale,
        platform: TargetPlatform.android,
        dark: v.dark,
        value: model(
          currencies: [figs(egp, safe: null)],
          cycle: Cycle(
            start: CivilDate(2026, 11, 24),
            end: CivilDate(2026, 12, 23),
          ),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_cycle_named_${v.name}.png'),
      );
    });
  }
}
