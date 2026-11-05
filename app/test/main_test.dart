import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/main.dart';

void main() {
  testWidgets('placeholder app renders an empty themed scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(const ZaghlolApp());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
