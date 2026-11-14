@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/golden_matrix.dart';
import 'review_harness.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('review queue golden ${v.name}', (tester) async {
      await pumpReview(
        tester,
        reviewApp(
          actions: FakeActions(),
          queue: sampleCards,
          locale: v.locale,
          dark: v.dark,
        ),
        size: const Size(390, 1500),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../../goldens/review_queue_${v.name}.png'),
      );
    });
  }
}
