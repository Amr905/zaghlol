// T-303: payday / saved-toast / vibration previews on the dev moods screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_haptics.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moods_screen.dart';
import 'package:zaghlol/features/mascot/presentation/payday_sheet.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

Widget _app(Locale l) => ProviderScope(
  overrides: [
    hideAmountsProvider.overrideWithValue(false),
    currentCycleOverviewProvider.overrideWith(
      (ref) async => CycleOverview(
        cycle: Cycle(
          start: CivilDate(2026, 11, 25),
          end: CivilDate(2026, 12, 25),
        ),
        today: CivilDate(2026, 11, 25),
        daysRemaining: 30,
        byCurrency: const {},
        incomeTarget: null,
      ),
    ),
    zaghlolArtboardProvider.overrideWithValue(
      (context, moment, talk, size) => SizedBox.square(dimension: size),
    ),
  ],
  child: MaterialApp(
    theme: ZaghlolTheme.light,
    locale: l,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const MascotMoodsScreen(),
  ),
);

void main() {
  for (final l in ['ar', 'en']) {
    testWidgets('previews: payday, toast, vibration ($l)', (t) async {
      await t.binding.setSurfaceSize(const Size(420, 2200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final plays = <int>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ZHaptics.channel,
        (c) async {
          plays.add((c.arguments as Map)['hits'].length as int);
          return true;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ZHaptics.channel,
          null,
        ),
      );
      await t.pumpWidget(_app(Locale(l)));
      await t.pumpAndSettle();

      // Vibration: one call per pattern, with that pattern's beats.
      for (final p in ZHapticPattern.values) {
        await t.tap(find.byKey(Key('try-vib-${p.name}')));
        await t.pump();
        expect(plays.last, ZHaptics.hits(p).length);
      }
      expect(plays.length, ZHapticPattern.values.length);

      // Toast with and without the budget line.
      await t.tap(find.byKey(const Key('try-toast-plain')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('savedToast')), findsOneWidget);
      await t.tap(find.byKey(const Key('try-toast-budget')));
      await t.pump(const Duration(milliseconds: 800));
      expect(find.byKey(const ValueKey('savedToast')), findsOneWidget);
      final t2 = AppLocalizations.of(t.element(find.byType(Scaffold).first));
      expect(find.text(t2.devTryToastBudgetLine), findsOneWidget);

      // Payday sheet opens for both currencies, no writes (no DB at all).
      for (final id in ['try-payday-egp', 'try-payday-usd']) {
        await t.tap(find.byKey(Key(id)));
        await t.pump(const Duration(milliseconds: 600));
        expect(find.byType(PaydaySheet), findsOneWidget);
        Navigator.of(t.element(find.byType(PaydaySheet))).pop();
        await t.pumpAndSettle(const Duration(milliseconds: 200));
        expect(find.byType(PaydaySheet), findsNothing);
      }
    });
  }

  testWidgets('vibration off shows why nothing is felt', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    ZHaptics.enabled = false;
    addTearDown(() => ZHaptics.enabled = true);
    await t.pumpWidget(_app(const Locale('en')));
    await t.pumpAndSettle();
    expect(find.textContaining('Vibration is off'), findsOneWidget);
  });
}
