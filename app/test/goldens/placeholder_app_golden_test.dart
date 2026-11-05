@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/main.dart';

void main() {
  testWidgets('placeholder app golden (light, ltr)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ZaghlolApp());

    await expectLater(
      find.byType(ZaghlolApp),
      matchesGoldenFile('placeholder_app.png'),
    );
  });
}
