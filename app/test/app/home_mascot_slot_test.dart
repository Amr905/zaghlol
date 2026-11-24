// FU-224: the Home mascot slot shows the picked line, in ar and en.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/home_mascot_slot.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/home/application/home_mascot.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moments.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart'
    show HomeActions;
import 'package:zaghlol_domain/zaghlol_domain.dart';

Widget _host(HomeMascotMessage? message, Locale locale, {CivilDate? payday}) =>
    ProviderScope(
      overrides: [
        paydayCelebrationProvider.overrideWith((ref) => Stream.value(payday)),
        homeMascotMessageProvider.overrideWith((ref) async => message),
        homeCardsProvider.overrideWith((ref, hasTx) async => const HomeCards()),
      ],
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: ZaghlolTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: HomeMascotSlot(actions: HomeActions()),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('payday celebrates once (${locale.languageCode})', (t) async {
      await t.pumpWidget(_host(null, locale, payday: CivilDate(2026, 11, 25)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot-payday')), findsOneWidget);
      final bird = t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar));
      expect(bird.moment, ZaghlolMoment.payday);
    });

    testWidgets('no payday: no payday bubble (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(_host(null, locale));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot-payday')), findsNothing);
    });
  }

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('saved-more line (${locale.languageCode})', (t) async {
      await t.pumpWidget(
        _host(MascotSavedMore(Money(Currency.of('EGP'), 300000)), locale),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot')), findsOneWidget);
    });

    testWidgets('no message: no bubble (${locale.languageCode})', (t) async {
      await t.pumpWidget(_host(null, locale));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot')), findsNothing);
    });
  }

  testWidgets('on-track line text (en)', (t) async {
    await t.pumpWidget(
      _host(MascotOnTrack(Currency.of('EGP')), const Locale('en')),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('under plan'), findsOneWidget);
  });

  // T-239: tapping the Home tip stays in the app, plays the tap mood and
  // rotates the line (T-215).
  testWidgets('tapping the tip keeps the app, tap mood, next line', (t) async {
    await t.pumpWidget(
      _host(MascotOnTrack(Currency.of('EGP')), const Locale('en')),
    );
    await t.pumpAndSettle();
    final before = t.widget<ZaghlolTapBubble>(find.byType(ZaghlolTapBubble));
    expect(find.textContaining('under plan'), findsOneWidget);
    await t.tap(find.byType(ZaghlolTapBubble));
    await t.pump();
    expect(find.textContaining('under plan'), findsNothing);
    expect(find.byType(ZaghlolTapBubble), findsOneWidget);
    expect(
      t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar)).moment,
      ZaghlolMoment.tap,
    );
    expect(
      WidgetsBinding.instance.lifecycleState,
      isNot(AppLifecycleState.paused),
    );
    expect(before.message, contains('under plan'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
