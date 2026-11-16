// UI-fix30: the Home hero opens the budget overview as a pushed route. It
// must sit in its own Scaffold/Material (a bare tab body renders black with
// yellow-underlined text).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_screens.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_screen.dart';

import '../features/budget/presentation/budget_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      testWidgets('budget route has Scaffold + Material ${locale.languageCode}'
          '${dark ? ' dark' : ''}', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            Builder(
              builder: (c) => TextButton(
                onPressed: () =>
                    const AppScreens().budget(c, onCategoryTap: (_, _) {}),
                child: const Text('open'),
              ),
            ),
            locale: locale,
            dark: dark,
            overrides: [
              budgetScreenDataProvider.overrideWith(
                (ref) async => data([egpView(budget: false)]),
              ),
            ],
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final screen = find.byType(BudgetScreen);
        expect(screen, findsOneWidget);
        expect(
          find.ancestor(of: screen, matching: find.byType(Scaffold)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: screen, matching: find.byType(Material)),
          findsWidgets,
        );
        // No fallback text style (yellow double underline).
        for (final t in tester.widgetList<Text>(
          find.descendant(of: screen, matching: find.byType(Text)),
        )) {
          final style = DefaultTextStyle.of(tester.element(find.byWidget(t)));
          expect(style.style.decoration, isNot(TextDecoration.underline));
          expect(style.style.decoration, isNot(TextDecoration.combine([])));
          expect(
            style.style.decorationStyle,
            isNot(TextDecorationStyle.double),
          );
        }
        final bg = tester
            .widget<Scaffold>(
              find.ancestor(of: screen, matching: find.byType(Scaffold)),
            )
            .backgroundColor;
        expect(bg, ZColors.of(tester.element(screen)).bg);
      });
    }
  }
}
