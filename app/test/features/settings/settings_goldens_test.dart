@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import 'settings_harness.dart';

void main() {
  const screens = <String, Widget>{
    'main': SettingsMainScreen(),
    'preferences': PreferencesScreen(),
    'privacy': PrivacyScreen(platform: 'ios'),
    'about': AboutScreen(),
  };
  for (final e in screens.entries) {
    for (final lang in ['ar', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('${e.key} $lang ${dark ? 'dark' : 'light'}', (
          tester,
        ) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          await tester.pumpWidget(
            h.app(
              e.value,
              locale: Locale(lang),
              dark: dark,
              payday: 25,
              appLock: true,
              overrides: [
                supportCodeProvider.overrideWith((ref) async => 'abc-123'),
              ],
            ),
          );
          await settle(tester, height: 1400);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/settings_${e.key}_${lang}_${dark ? 'dark' : 'light'}.png',
            ),
          );
        });
      }
    }
  }
}
