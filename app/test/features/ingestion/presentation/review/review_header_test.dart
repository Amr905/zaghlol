import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_header.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import '../../../../support/golden_matrix.dart';
import '../../../../support/l10n_golden.dart';

void main() {
  const expected = {
    'en': {
      1: '1 message needs a look',
      3: '3 messages need a look',
      11: '11 messages need a look',
    },
    'ar': {
      1: 'رسالة واحدة محتاجة نظرة',
      3: '3 رسايل محتاجين نظرة',
      11: '11 رسالة محتاجين نظرة',
    },
  };
  for (final v in goldenVariants.where((v) => !v.dark)) {
    for (final n in [1, 3, 11]) {
      testWidgets('header plural n=$n ${v.name}', (t) async {
        await t.pumpWidget(
          l10nGoldenHost(v, ReviewHeader(count: n, countText: '$n')),
        );
        expect(find.text(expected[v.locale.languageCode]![n]!), findsOneWidget);
        final bird = t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar));
        expect(bird.moment, ZaghlolMoment.detective);
        expect(bird.size, 64);
      });
    }
  }
}
