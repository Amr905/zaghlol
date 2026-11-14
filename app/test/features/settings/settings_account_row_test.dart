// S-60 Account row: the way into S-69 other than the Gold sign-in buttons.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';

import 'settings_harness.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    testWidgets('Account row opens its destination ($lang, 1.3x)', (t) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      var opened = 0;
      await t.pumpWidget(
        h.app(
          SettingsMainScreen(
            destinations: SettingsDestinations(onAccount: () => opened++),
          ),
          locale: Locale(lang),
          scale: 1.3,
        ),
      );
      await settle(t);
      final label = AppLocalizations.of(
        t.element(find.byType(SettingsMainScreen)),
      ).goldAccountTitle;
      final row = find.byKey(const ValueKey('settings-account'));
      expect(
        find.descendant(of: row, matching: find.text(label)),
        findsOneWidget,
      );
      expect(t.getSize(row).height, greaterThanOrEqualTo(48));
      await t.tap(row);
      expect(opened, 1);
      expect(t.takeException(), isNull);
    });
  }
}
