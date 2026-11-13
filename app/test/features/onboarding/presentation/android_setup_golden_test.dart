@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import 'android_setup_test.dart' show FakeHost, FakeScan, host;

void main() {
  final cases = <String, FakeHost>{
    'sms': FakeHost(),
    'notif': FakeHost(granted: true),
    'nosms': FakeHost(flavor: false),
  };
  for (final e in cases.entries) {
    for (final v in goldenVariants) {
      testWidgets('android setup ${e.key} golden ${v.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('golden-root'),
            child: host(e.value, FakeScan(), v.locale.languageCode),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('android_setup_${e.key}_${v.name}.png'),
        );
      });
    }
  }
}
