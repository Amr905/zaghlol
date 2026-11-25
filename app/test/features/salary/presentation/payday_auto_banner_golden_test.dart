@Tags(['golden'])
library;

// FU-296 m-5 (T-247): ar + en goldens of the Home payday-auto banner, plain
// and for a capped 29-31 salary. The banner is pumped on its own (Home's
// goldens keep their fixed model); nothing in it depends on the clock.
// Update with --update-goldens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/salary/presentation/payday_auto_banner.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../settings/settings_harness.dart';

void main() {
  const states = {
    'plain': PaydayAutoState(autoDay: 23, previous: 10, bannerPending: true),
    'capped': PaydayAutoState(autoDay: 28, salaryDay: 30, bannerPending: true),
  };
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final e in states.entries) {
      testWidgets('payday banner golden ${e.key} ${locale.languageCode}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 240));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final h = SettingsHarness();
        addTearDown(h.db.close);
        await tester.pumpWidget(
          h.app(
            const Scaffold(body: PaydayAutoBanner()),
            locale: locale,
            overrides: [
              paydayAutoProvider.overrideWith((ref) => Stream.value(e.value)),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/payday_banner_${e.key}_${locale.languageCode}.png',
          ),
        );
      });
    }
  }
}
