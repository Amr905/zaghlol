// T-246 (D-81): the payday-auto banner in ar and en, with Undo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/budget/data/payday_schedule_store.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/salary/application/payday_auto_service.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/salary/presentation/payday_auto_banner.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../settings/settings_harness.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final isAr = locale.languageCode == 'ar';

    testWidgets('banner (${locale.languageCode}): text, Undo restores', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      final store = PaydayScheduleStore(
        h.repo,
        nowUtcMs: () => 1793000000000,
        zone: const FixedLocalZone(120),
      );
      await tester.runAsync(() async {
        await store.setPayday(10);
        await store.setPayday(23);
        await h.repo.set(
          Settings.paydayAuto,
          const PaydayAutoState(autoDay: 23, previous: 10, bannerPending: true),
        );
      });
      await tester.pumpWidget(
        h.app(
          const Scaffold(body: PaydayAutoBanner()),
          locale: locale,
          overrides: [
            paydayAutoProvider.overrideWith(
              (ref) => Stream.value(
                const PaydayAutoState(
                  autoDay: 23,
                  previous: 10,
                  bannerPending: true,
                ),
              ),
            ),
            paydayAutoServiceProvider.overrideWith(
              (ref) async => PaydayAutoService(
                h.db,
                h.repo,
                store,
                nowUtcMs: () => 1793000000000,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payday-auto-banner')), findsOne);
      expect(
        find.textContaining(isAr ? 'خلّيت يوم القبض ٢٣' : 'payday to day 23'),
        findsOne,
      );
      expect(find.text(isAr ? 'تراجع' : 'Undo'), findsOne);
      await tester.runAsync(() async {
        await tester.tap(find.text(isAr ? 'تراجع' : 'Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      expect(await tester.runAsync(() => h.repo.get(Settings.paydayDay)), 10);
    });
  }

  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final isAr = locale.languageCode == 'ar';
    testWidgets('capped salary (${locale.languageCode}): names the real day', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      const state = PaydayAutoState(
        autoDay: 28,
        salaryDay: 30,
        bannerPending: true,
      );
      await tester.pumpWidget(
        h.app(
          const Scaffold(body: PaydayAutoBanner()),
          locale: locale,
          overrides: [
            paydayAutoProvider.overrideWith((ref) => Stream.value(state)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(isAr ? 'يوم القبض ٢٨' : 'payday to day 28'),
        findsOne,
      );
      expect(
        find.textContaining(isAr ? 'بينزل يوم ٣٠' : 'lands on day 30'),
        findsOne,
      );
    });
  }

  testWidgets('no banner when nothing is pending', (tester) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    await tester.pumpWidget(
      h.app(
        const Scaffold(body: PaydayAutoBanner()),
        overrides: [
          paydayAutoProvider.overrideWith(
            (ref) => Stream.value(PaydayAutoState.empty),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payday-auto-banner')), findsNothing);
  });
}
