// T-232: the developer "Zaghlol's moods" screen: one button per moment, a
// talk switch, the right moment reaches the avatar, and it exists in dev
// builds only (the About row and the provider default).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moods_screen.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';

import '../../settings/settings_harness.dart';

Widget _app(Locale locale, List<ZaghlolMoment> seen, List<bool> talks) {
  return ProviderScope(
    overrides: [
      zaghlolArtboardProvider.overrideWithValue((context, moment, talk, size) {
        seen.add(moment);
        talks.add(talk);
        return SizedBox.square(dimension: size);
      }),
    ],
    child: MaterialApp(
      theme: ZaghlolTheme.light,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MascotMoodsScreen(),
    ),
  );
}

void main() {
  for (final l in ['ar', 'en']) {
    testWidgets('one button per moment; each plays on the avatar ($l)', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final seen = <ZaghlolMoment>[];
      final talks = <bool>[];
      await t.pumpWidget(_app(Locale(l), seen, talks));
      await t.pumpAndSettle();
      for (final m in ZaghlolMoment.values) {
        final b = find.byKey(Key('mood-${m.name}'));
        expect(b, findsOneWidget);
        expect(t.getSize(b).height, greaterThanOrEqualTo(48));
        await t.tap(b);
        await t.pump();
        expect(seen.last, m);
      }
      // Same button twice replays (the avatar is rebuilt).
      final before = seen.length;
      await t.tap(find.byKey(const Key('mood-tap')));
      await t.pump();
      await t.tap(find.byKey(const Key('mood-tap')));
      await t.pump();
      expect(seen.length, greaterThan(before));
      await t.tap(find.byKey(const Key('moods-talk')));
      await t.pump();
      expect(talks.last, isTrue);
    });
  }

  testWidgets('reduce motion shows a note (the bird stays still)', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _app(const Locale('en'), [], []),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('moods-reduce-note')), findsOneWidget);
  });

  test('the screen is off in a plain build (staging and prod)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(mascotMoodsEnabledProvider), isFalse);
  });

  testWidgets('About shows the moods row only when the dev switch is on', (
    t,
  ) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    Future<void> pumpAbout(bool on) async {
      await t.pumpWidget(
        h.app(
          const AboutScreen(),
          overrides: [mascotMoodsEnabledProvider.overrideWithValue(on)],
        ),
      );
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    await pumpAbout(false);
    expect(find.text("Zaghlol's moods"), findsNothing);
    await pumpAbout(true);
    expect(find.text("Zaghlol's moods"), findsOneWidget);
  });
}
