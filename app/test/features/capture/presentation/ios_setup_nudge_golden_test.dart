@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/application/ios_nudge_providers.dart';
import 'package:zaghlol/features/capture/presentation/ios_setup_nudge.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';

import '../../settings/settings_harness.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
        'settings with the iOS nudge $lang ${dark ? 'dark' : 'light'}',
        (tester) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          await tester.pumpWidget(
            h.app(
              SettingsMainScreen(
                destinations: SettingsDestinations(onCapture: () {}),
              ),
              locale: Locale(lang),
              dark: dark,
              overrides: [iosNudgeDaysProvider.overrideWithValue(9)],
            ),
          );
          await settle(tester, height: 1400);
          expect(find.byType(IosSetupNudge), findsOneWidget);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/settings_nudge_${lang}_${dark ? 'dark' : 'light'}.png',
            ),
          );
        },
      );
    }
  }
}
