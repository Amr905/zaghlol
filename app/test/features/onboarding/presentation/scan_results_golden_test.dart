@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'scan_results_test.dart' show host, sample;

import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('scan results golden ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('golden-root'),
          child: host(
            const AsyncData(sample),
            v.locale.languageCode,
            dark: v.dark,
            scale: v.textScale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('scan_results_${v.name}.png'),
      );
    });
  }
}
