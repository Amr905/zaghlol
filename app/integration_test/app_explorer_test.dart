// TEST-explorer: the "tap everything" run on the REAL app (`main()`, real
// providers, real encrypted database, real plugins) on the Android emulator,
// in Arabic, with synthetic data: accounts including a credit card, 30
// transactions in EGP and USD, a budget, a recurring bill, review items.
//
// It visits every tab, the Add sheet and every screen reachable from them,
// taps every tappable widget on each screen (see support/explorer.dart),
// goes back after each tap, takes a screenshot of every screen and writes a
// report (screen -> taps -> issues) to the app's private documents dir
// (`ci_screens/explorer-report.md`), which .github/scripts/device-flows.sh
// pulls. Nothing here logs financial data (it is all synthetic anyway).
//
// Run: flutter test integration_test/app_explorer_test.dart --flavor devSms
//      -d <device> --no-uninstall

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/catalog/catalog_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/z_button.dart' show ZButton;
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZAddButton;
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/explorer.dart';
import 'support/explorer_seed.dart';

// One part per run (a fresh app process each): 0-3 = the four tabs, 4 = the
// Add sheet, -1 = all. A single long run exhausted the app's Java heap.
const _part = int.fromEnvironment('EXPLORER_PART', defaultValue: -1);

// FU-245: which variant of the run. `ar` (default) is the original Arabic
// light run; `en` English; `dark` the dark theme (Arabic); `scale` Arabic at
// the system text scale 1.3 (device-flows.sh sets `font_scale` first);
// `onboarding` / `onboarding_en` a fresh install walked through the
// first-run flow; `paywall` the Gold paywall (S-68). The variants explore
// two levels deep so that one app process stays within the heap.
const _mode = String.fromEnvironment('EXPLORER_MODE', defaultValue: 'ar');
const _fresh = _mode == 'onboarding' || _mode == 'onboarding_en';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;

  Future<Directory> outDir() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/ci_screens',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> shot(WidgetTester t, String name) async {
    try {
      if (!surfaceConverted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      await t.pump(const Duration(milliseconds: 300));
      final bytes = await binding.takeScreenshot('$_mode-p$_part-$name');
      await File('${(await outDir()).path}/$_mode-p$_part-$name.png')
          .writeAsBytes(bytes);
    } on Object catch (e) {
      // A screenshot is evidence, not the test: report the type only.
      // ignore: avoid_print
      print('EXPLORER_SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  testWidgets('explorer[$_mode]: taps every control of every screen', (
    t,
  ) async {
    final started = DateTime.now();

    // ---- A returning Arabic user with synthetic data.
    final dir = await resolveDbDirectory();
    final seed = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    final settings = await seed.read(settingsRepositoryProvider.future);
    final now = DateTime.now();
    if (!_fresh) {
      await settings.set(
        Settings.setupInstalledOn,
        CivilDate(now.year, now.month, now.day).epochDay,
      );
    }
    await settings.set(
      Settings.language,
      _mode == 'en' || _mode == 'onboarding_en'
          ? LanguagePref.en
          : LanguagePref.ar,
    );
    if (_mode == 'dark') await settings.set(Settings.theme, ThemePref.dark);
    try {
      await seed.read(catalogSeedProvider.future);
    } on Object {
      // Categories stay empty; the run still explores.
    }
    // ignore: avoid_print
    print('EXPLORER_STAGE catalog ready');
    final seeded = _fresh
        ? const ExplorerSeedResult(
            accountIds: [],
            transactions: 0,
            reviewItems: 0,
          )
        : await seedExplorerData(seed).timeout(
            const Duration(minutes: 2),
            onTimeout: () => throw StateError('seeding timed out'),
          );
    // ignore: avoid_print
    print(
      'EXPLORER_SEEDED accounts=${seeded.accountIds.length} '
      'txns=${seeded.transactions} reviews=${seeded.reviewItems}',
    );
    // ignore: avoid_print
    print('EXPLORER_STAGE seeded; closing the seed database');
    await Future<void>.delayed(const Duration(seconds: 1));
    seed.dispose();
    await Future<void>.delayed(const Duration(seconds: 1));
    // ignore: avoid_print
    print('EXPLORER_STAGE starting the app');

    await app.main();
    // ignore: avoid_print
    print('EXPLORER_STAGE main() returned');
    final bar = find.byType(NavigationBar);
    final welcome = find.byType(ZButton);
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end) &&
        bar.evaluate().isEmpty &&
        !(_fresh && welcome.evaluate().isNotEmpty)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print(
      'EXPLORER_STAGE mode=$_mode textScale='
      '${t.platformDispatcher.textScaleFactor} '
      'shell shown: ${bar.evaluate().isNotEmpty}',
    );
    if (_mode == 'scale') {
      expect(t.platformDispatcher.textScaleFactor, greaterThan(1.2));
    }
    if (_fresh) {
      await _walkOnboarding(t, bar, (n) => shot(t, n));
      if (_mode == 'onboarding' || _mode == 'onboarding_en') {
        expect(bar, findsOneWidget, reason: 'onboarding ends on the shell');
        return;
      }
    }
    expect(bar, findsOneWidget, reason: 'the shell shows');
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    // Both languages: the setting loads a moment after the first frame, so
    // the context's own locale is not reliable here.
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
    // Labels that would leave the app (links, share sheet, system settings),
    // sign the user out, delete data or change the language: never tapped.
    Set<String> both(String Function(AppLocalizations) f) => {
      f(l10n),
      f(l10nEn),
    };
    final deny = <String>{
      ...both((l) => l.goldPaywallTerms),
      ...both((l) => l.goldPaywallPrivacy),
      ...both((l) => l.aboutMainTerms),
      ...both((l) => l.aboutMainPrivacy),
      ...both((l) => l.legalTermsOpen),
      ...both((l) => l.onboardingWelcomePrivacyLink),
      ...both((l) => l.goldAccountManage),
      ...both((l) => l.shareStudioShare),
      ...both((l) => l.aboutDiagShare),
      ...both((l) => l.commonActionOpenSettings),
      ...both((l) => l.commonActionSignOut),
      ...both((l) => l.privacyDeleteConfirm),
      ...both((l) => l.goldAccountDeleteConfirm),
      // Changing the language would turn the Arabic run into an English one.
      ...both((l) => l.settingsPrefsLanguageAr),
      ...both((l) => l.settingsPrefsLanguageEn),
      // ... or the digits or the theme under the rest of the run.
      ...both((l) => l.settingsPrefsDigitsWestern),
      ...both((l) => l.settingsPrefsThemeDark),
      ...both((l) => l.settingsPrefsThemeLight),
      ...both((l) => l.settingsPrefsThemeSystem),
    };

    Future<void> selectTab(int i) async {
      final dest = find.descendant(
        of: bar,
        matching: find.byType(NavigationDestination),
      );
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (DateTime.now().isBefore(end) && dest.evaluate().length <= i) {
        await t.pump(const Duration(milliseconds: 250));
      }
      if (dest.evaluate().length <= i) {
        // ignore: avoid_print
        print('EXPLORER_STAGE no tab bar to select tab $i');
        return;
      }
      await t.tap(dest.at(i));
      await t.pump(const Duration(milliseconds: 600));
    }

    Future<void> goHome() async {
      // Screens pushed on the root navigator (Settings, ...) hide the shell.
      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      await t.pump(const Duration(milliseconds: 500));
      GoRouter.of(rootNavigatorKey.currentContext!).go(AppRoutes.home);
      await t.pump(const Duration(milliseconds: 600));
      await selectTab(0);
    }

    Future<void> openAdd() async {
      await t.tap(find.byType(ZAddButton).first);
      await t.pump(const Duration(milliseconds: 700));
    }

    final report = File('${(await outDir()).path}/explorer-report-p$_part.md');
    late final Explorer ex;
    ex = Explorer(
      tester: t,
      shot: (n) => shot(t, n),
      deadline: started.add(const Duration(minutes: 12)),
      goHome: goHome,
      selectTab: selectTab,
      deny: deny,
      log: (line) {
        // ignore: avoid_print
        print(
          line.startsWith('EXPLORER_SCREEN')
              ? '$line rssMB=${ProcessInfo.currentRss ~/ 1048576}'
              : line,
        );
      },
      navLabels: {
        ...both((l) => l.commonActionBackA11y),
        ...both((l) => l.commonActionClose),
      },
      maxDepth: _mode == 'ar' ? 4 : 1,
      onUpdate: (md) => report.writeAsStringSync(md),
    )..install();

    final names = [
      l10n.commonNavHome,
      l10n.commonNavInsights,
      l10n.commonNavMoney,
      l10n.commonNavZaghlol,
    ];
    // Errors thrown asynchronously by tap handlers reach the zone, not
    // FlutterError.onError; without this guard the first one ends the test.
    final done = Completer<void>();
    final uncaught = <Object>[];
    unawaited(
      runZonedGuarded(
        () async {
          try {
            if (_mode == 'paywall') {
              Future<void> openPaywall() async {
                unawaited(
                  rootNavigatorKey.currentState?.push<bool>(
                    MaterialPageRoute<bool>(
                      fullscreenDialog: true,
                      builder: (_) => const PaywallScreen(),
                    ),
                  ),
                );
                await t.pump(const Duration(milliseconds: 900));
              }

              await openPaywall();
              await ex.exploreCurrent(
                l10n.goldPaywallTitle,
                reopen: openPaywall,
              );
              await goHome();
            }
            for (var i = 0; i < 4 && !ex.timedOut && _mode != 'paywall'; i++) {
              if (_part >= 0 && _part != i) continue;
              await selectTab(i);
              await ex.exploreCurrent(
                names[i],
                tabIndex: i,
                reopen: () => selectTab(i),
              );
              await goHome();
            }
            if (!ex.timedOut &&
                _mode != 'paywall' &&
                (_part < 0 || _part == 4)) {
              await selectTab(0);
              await openAdd();
              await ex.exploreCurrent(l10n.commonNavAddA11y, reopen: openAdd);
              await rootNavigatorKey.currentState?.maybePop();
              await goHome();
            }
          } finally {
            done.complete();
          }
        },
        (e, s) {
          uncaught.add(e);
          ex.recordUncaught(e, s);
        },
      ),
    );
    try {
      await done.future;
    } finally {
      ex.uninstall();
      final md = ex.markdown(
        title:
            'Explorer run ${now.toIso8601String().substring(0, 10)} '
            '(Android emulator, mode $_mode, synthetic data)',
      );
      report.writeAsStringSync(md);
      // ignore: avoid_print
      print(
        'EXPLORER_DONE screens=${ex.screens.length} taps=${ex.tapCount} '
        'issues=${ex.totalIssues} deadTaps=${ex.deadTaps} '
        'minutes=${DateTime.now().difference(started).inMinutes}',
      );
      // The whole report, so it survives in the job log.
      for (final line in md.split('\n')) {
        // ignore: avoid_print
        print('EXPLORER_REPORT $line');
      }
    }

    final hard = [
      for (final s in ex.screens)
        for (final i in s.issues)
          // The emulator has no backend: an offline failure is expected,
          // but it still shows in the report (an open finding).
          if (i.kind != 'dead-tap' &&
              i.kind != 'restore' &&
              i.kind != 'dead-end' &&
              !i.detail.contains('BackendFailure(offline)'))
            '${s.title}: ${i.kind} ${i.where}',
    ];
    expect(
      ex.screens.length,
      greaterThan(_part < 0 && _mode == 'ar' ? 8 : 0),
      reason: 'explored real screens',
    );
    expect(hard, isEmpty, reason: hard.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/// A fresh install: shots of the welcome screen in both languages, then
/// Start, the setup screens (taps "allow SMS" first where it is offered, then
/// the last button, which moves on) until the shell shows.
Future<void> _walkOnboarding(
  WidgetTester t,
  Finder bar,
  Future<void> Function(String name) shot,
) async {
  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  await settle();
  await shot('onb-0-welcome');
  final l10n = {
    for (final c in const ['ar', 'en'])
      c: await AppLocalizations.delegate.load(Locale(c)),
  };
  final toggle = find.byKey(const ValueKey('welcome-language-toggle'));
  if (toggle.evaluate().isNotEmpty) {
    await t.tap(toggle.first);
    await settle();
    await shot('onb-0b-welcome-other-language');
    await t.tap(toggle.first);
    await settle();
  }
  final skip = {
    for (final l in l10n.values) ...{
      l.onboardingWelcomeRestore,
      l.onboardingWelcomePrivacyLink,
      l.commonActionOpenSettings,
    },
  };
  final buttons = find.byWidgetPredicate(
    (w) => w is ZButton && w.onPressed != null && !skip.contains(w.label),
  );
  for (var step = 1; step <= 10 && bar.evaluate().isEmpty; step++) {
    if (buttons.evaluate().isEmpty) break;
    // The first screen has Start first; the later ones end with "continue".
    final target = step == 1 ? buttons.first : buttons.last;
    await t.tap(target);
    await settle();
    await shot('onb-$step');
  }
  for (var i = 0; i < 40 && bar.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  await shot('onb-end');
}
