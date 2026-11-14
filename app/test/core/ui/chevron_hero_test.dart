import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_components.dart';

Widget _app(Widget child, TextDirection d) => MaterialApp(
  theme: ZaghlolTheme.light,
  home: Directionality(
    textDirection: d,
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final d in TextDirection.values) {
    testWidgets('list row chevron mirrors once in $d', (tester) async {
      await tester.pumpWidget(
        _app(ZListRow(title: 'x', showChevron: true, onTap: () {}), d),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.chevron_right);
      final rect = tester.getRect(find.byType(Icon));
      final row = tester.getRect(find.byType(ZListRow));
      if (d == TextDirection.rtl) {
        expect(rect.left, lessThan(row.center.dx)); // trailing edge = left
      } else {
        expect(rect.left, greaterThan(row.center.dx));
      }
      // Icons.chevron_right has matchTextDirection, so Flutter flips it.
      expect(icon.icon!.matchTextDirection, isTrue);
    });
  }

  testWidgets('tappable hero keeps inner buttons as separate nodes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var inner = 0;
    await tester.pumpWidget(
      _app(
        ZHeroCard(
          onTap: () {},
          child: Column(
            children: [
              const Text('Hero label'),
              TextButton(
                onPressed: () => inner++,
                child: const Text('Set budget'),
              ),
            ],
          ),
        ),
        TextDirection.ltr,
      ),
    );
    expect(
      tester.getSemantics(find.text('Set budget')),
      matchesSemantics(
        label: 'Set budget',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Set budget'));
    expect(inner, 1);
    handle.dispose();
  });
}
