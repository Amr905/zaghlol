// T-174: guideline + 1.3x sweep over Paywall, Ask, Money tab and the wealth
// screens.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';

import '../features/ask/presentation/ask_screen_test.dart' as ask;
import '../features/money/money_tab_test.dart' as money;
import '../features/gold/presentation/gold_ui_harness.dart';
import '../features/wealth/presentation/assets_ui_test.dart' as wealth;
import '../support/a11y_guidelines.dart';
import '../support/golden_matrix.dart';

Future<void> main() async {
  await initDateFormatting();
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    testWidgets('paywall a11y ${v.name}', (t) async {
      await pumpGold(
        t,
        goldApp(
          const PaywallScreen(),
          overrides: goldOverrides(FakeGoldActions()),
          lang: v.locale.languageCode,
          dark: v.dark,
          scale: v.textScale,
        ),
        height: 1400,
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('ask a11y ${v.name}', (t) async {
      await ask.pump(
        t,
        ask.FakeEngine((_, _) async => ask.compare()),
        locale: v.locale,
        dark: v.dark,
        scale: v.textScale,
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('money tab a11y ${v.name}', (t) async {
      await money.pumpForGolden(t, v);
      await expectA11yGuidelines(t);
    });

    for (final screen in const ['assets', 'add_asset', 'prices']) {
      testWidgets('$screen a11y ${v.name}', (t) async {
        await wealth.pumpScreenForGolden(t, screen, v);
        await expectA11yGuidelines(t);
      });
    }
  }
}
