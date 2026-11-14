// T-174: a tappable ZCard exposes one labelled button node (regression for the
// unlabelled tap node found on Home's review card).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_card.dart';

import '../support/a11y_guidelines.dart';

void main() {
  testWidgets('tappable ZCard is labelled by its text', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ZaghlolTheme.light,
        home: Scaffold(
          body: ZCard(onTap: () {}, child: const Text('Review 3')),
        ),
      ),
    );
    await expectA11yGuidelines(t);
    final h = t.ensureSemantics();
    expect(find.bySemanticsLabel('Review 3'), findsOneWidget);
    h.dispose();
  });
}
