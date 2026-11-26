// FU-224: the Home mascot slot shows the picked line, in ar and en.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/home_mascot_slot.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/home/application/home_mascot.dart';
import 'package:zaghlol/features/mascot/application/mascot_tips.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moments.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart'
    show HomeActions;
import 'package:zaghlol_domain/zaghlol_domain.dart';

Widget _host(
  HomeMascotMessage? message,
  Locale locale, {
  PaydayCelebration? payday,
  MascotTip? tip,
}) => ProviderScope(
  overrides: [
    paydayCelebrationProvider.overrideWith((ref) => Stream.value(payday)),
    homeMascotMessageProvider.overrideWith((ref) async => message),
    homeTipProvider.overrideWith((ref) async => tip),
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
  _routeTests();
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('payday opens the sheet, no bubble (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          null,
          locale,
          payday: PaydayCelebration('s1', Money(Currency.of('EGP'), 2970000)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-mascot-payday')), findsNothing);
      final bird = t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar));
      expect(bird.moment, ZaghlolMoment.payday);
    });

    testWidgets('no payday: no payday bubble (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(_host(null, locale));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('payday-amount')), findsNothing);
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

  // T-277: a tip fills an empty slot only.
  final tip = mascotTips.firstWhere(
    (t) => t.target != MascotTipTarget.none && t.group == MascotTipGroup.usage,
  );
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('tip shows when nothing else does (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(_host(null, locale, tip: tip));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot-tip')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-mascot-tip-open')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'a tip never covers the payday sheet (${locale.languageCode})',
      (t) async {
        await t.pumpWidget(
          _host(
            null,
            locale,
            tip: tip,
            payday: PaydayCelebration('s1', Money(Currency.of('EGP'), 100)),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
      },
    );

    testWidgets('a tip never covers a proud line (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(
        _host(MascotOnTrack(Currency.of('EGP')), locale, tip: tip),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-mascot-tip')), findsNothing);
      expect(find.byKey(const ValueKey('home-mascot')), findsOneWidget);
    });
  }

  testWidgets('a text-only tip has no Show me button', (t) async {
    final text = mascotTips.firstWhere((t) => t.target == MascotTipTarget.none);
    await t.pumpWidget(_host(null, const Locale('en'), tip: text));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-mascot-tip')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-mascot-tip-open')), findsNothing);
  });
}

Widget _routed(
  PaydayCelebration payday, {
  required GlobalKey<NavigatorState> nav,
  required ValueNotifier<bool> active,
}) => ProviderScope(
  overrides: [
    paydayCelebrationProvider.overrideWith((ref) => Stream.value(payday)),
    homeMascotMessageProvider.overrideWith((ref) async => null),
    homeTipProvider.overrideWith((ref) async => null),
    homeCardsProvider.overrideWith((ref, hasTx) async => const HomeCards()),
    settingsRepositoryProvider.overrideWith(
      (ref) async => throw StateError('no db'),
    ),
  ],
  child: MaterialApp(
    navigatorKey: nav,
    theme: ZaghlolTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ValueListenableBuilder<bool>(
      valueListenable: active,
      builder: (_, on, _) => TickerMode(
        enabled: on,
        child: const Scaffold(
          body: SingleChildScrollView(
            child: HomeMascotSlot(actions: HomeActions()),
          ),
        ),
      ),
    ),
  ),
);

void _routeTests() {
  final salary = PaydayCelebration('s1', Money(Currency.of('EGP'), 500000));

  testWidgets('salary while Add is on top: sheet opens once after pop', (
    t,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final active = ValueNotifier(true);
    await t.pumpWidget(_routed(salary, nav: nav, active: active));
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('payday-amount')), findsNothing);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
  });

  testWidgets('salary on another tab: no sheet until Home is active', (
    t,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    final active = ValueNotifier(false);
    await t.pumpWidget(_routed(salary, nav: nav, active: active));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('payday-amount')), findsNothing);
    active.value = true;
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
  });
}
