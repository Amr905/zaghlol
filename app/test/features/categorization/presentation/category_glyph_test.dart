// Explorer finding: a catalog icon key (`shopping_bag`) was drawn as its own
// letters on the transaction detail, rows and pickers. categoryGlyph draws
// keys as icons and leaves emoji as text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/categorization/presentation/category_visuals.dart';

void main() {
  Future<void> pump(WidgetTester t, String icon) => t.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Center(child: categoryGlyph(icon, size: 24)),
    ),
  );

  testWidgets('an icon key draws an icon, not its letters', (t) async {
    await pump(t, 'shopping_bag');
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('shopping_bag'), findsNothing);
  });

  testWidgets('a known key maps to its icon', (t) async {
    await pump(t, 'cart');
    expect(
      t.widget<Icon>(find.byType(Icon)).icon,
      Icons.shopping_cart_outlined,
    );
  });

  testWidgets('an emoji stays text', (t) async {
    await pump(t, '🛍️');
    expect(find.text('🛍️'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the unknown-category dot stays text', (t) async {
    await pump(t, '•');
    expect(find.text('•'), findsOneWidget);
  });
}
