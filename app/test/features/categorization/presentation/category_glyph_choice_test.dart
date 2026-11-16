// batch-27 (FIX-category-icons minor): a custom category shows the icon the
// user chose; a system category keeps its emoji.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/category_glyph.dart';
import 'package:zaghlol/features/categorization/presentation/category_visuals.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: w)),
    ),
  );

  testWidgets('custom category: the chosen icon', (tester) async {
    await pump(
      tester,
      categoryGlyph(id: 'c-7f1', iconKey: 'pets', style: const TextStyle()),
    );
    expect(find.byIcon(Icons.pets_outlined), findsOneWidget);
    expect(find.text(ZCategoryGlyph.glyphFor('c-7f1')), findsNothing);
  });

  testWidgets('system category: its emoji, whatever the key', (tester) async {
    await pump(
      tester,
      categoryGlyph(
        id: 'sys:dining',
        iconKey: 'food',
        style: const TextStyle(),
      ),
    );
    expect(find.text(ZCategoryGlyph.glyphFor('sys:dining')), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('unknown key: the emoji fallback, never the key', (tester) async {
    await pump(
      tester,
      categoryGlyph(
        id: 'c-7f2',
        iconKey: 'receipt_long',
        style: const TextStyle(),
      ),
    );
    expect(find.text('receipt_long'), findsNothing);
    expect(find.text(ZCategoryGlyph.glyphFor('c-7f2')), findsOneWidget);
  });
}
