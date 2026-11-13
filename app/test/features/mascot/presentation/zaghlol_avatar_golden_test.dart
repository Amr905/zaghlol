@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import '../../../support/golden_matrix.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('zaghlol_avatar ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(200, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(child: goldenHarness(v, const ZaghlolAvatar(size: 160))),
      );
      await tester.runAsync(() async {
        await tester.pump();
        await precacheImage(
          const AssetImage(ZaghlolAvatar.stillAsset),
          tester.element(find.byType(ZaghlolAvatar)),
        );
      });
      await tester.pump();
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('../../../goldens/zaghlol_avatar_${v.name}.png'),
      );
    });
  }
}
