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
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZAddButton;
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/explorer.dart';
import 'support/explorer_seed.dart';

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
      final bytes = await binding.takeScreenshot(name);
      await File('${(await outDir()).path}/$name.png').writeAsBytes(bytes);
    } on Object catch (e) {
      // A screenshot is evidence, not the test: report the type only.
      // ignore: avoid_print
      print('EXPLORER_SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  testWidgets('explorer: taps every control of every screen, in Arabic', (
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
    await settings.set(
      Settings.setupInstalledOn,
      CivilDate(now.year, now.month, now.day).epochDay,
    );
    await settings.set(Settings.language, LanguagePref.ar);
    try {
      await seed.read(catalogSeedProvider.future);
    } on Object {
      // Categories stay empty; the run still explores.
    }
    // ignore: avoid_print
    print('EXPLORER_STAGE catalog ready');
    final seeded = await seedExplorerData(seed).timeout(
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
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end) && bar.evaluate().isEmpty) {
      await t.pump(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('EXPLORER_STAGE shell shown: ${bar.evaluate().isNotEmpty}');
    expect(bar, findsOneWidget, reason: 'the shell shows');
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    final l10n = AppLocalizations.of(rootNavigatorKey.currentContext!);
    // Labels that would leave the app (links, share sheet, system settings),
    // sign the user out or delete data: never tapped.
    final deny = <String>{
      l10n.goldPaywallTerms,
      l10n.goldPaywallPrivacy,
      l10n.aboutMainTerms,
      l10n.aboutMainPrivacy,
      l10n.legalTermsOpen,
      l10n.onboardingWelcomePrivacyLink,
      l10n.goldAccountManage,
      l10n.shareStudioShare,
      l10n.aboutDiagShare,
      l10n.commonActionOpenSettings,
      l10n.commonActionSignOut,
      l10n.privacyDeleteConfirm,
      l10n.goldAccountDeleteConfirm,
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

    final report = File('${(await outDir()).path}/explorer-report.md');
    late final Explorer ex;
    ex = Explorer(
      tester: t,
      shot: (n) => shot(t, n),
      deadline: started.add(const Duration(minutes: 24)),
      goHome: goHome,
      selectTab: selectTab,
      deny: deny,
      navLabels: {l10n.commonActionBackA11y, l10n.commonActionClose},
      maxDepth: 4,
      onUpdate: (md) => report.writeAsStringSync(md),
    )..install();

    final names = [
      l10n.commonNavHome,
      l10n.commonNavInsights,
      l10n.commonNavMoney,
      l10n.commonNavZaghlol,
    ];
    try {
      for (var i = 0; i < 4 && !ex.timedOut; i++) {
        await selectTab(i);
        await ex.exploreCurrent(
          names[i],
          tabIndex: i,
          reopen: () => selectTab(i),
        );
        await goHome();
      }
      if (!ex.timedOut) {
        await selectTab(0);
        await openAdd();
        await ex.exploreCurrent(l10n.commonNavAddA11y, reopen: openAdd);
        await rootNavigatorKey.currentState?.maybePop();
        await goHome();
      }
    } finally {
      ex.uninstall();
      final md = ex.markdown(
        title:
            'Explorer run ${now.toIso8601String().substring(0, 10)} '
            '(Android emulator, Arabic, synthetic data)',
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
          if (i.kind != 'dead-tap') '${s.title}: ${i.kind} ${i.where}',
    ];
    expect(ex.screens.length, greaterThan(8), reason: 'explored real screens');
    expect(hard, isEmpty, reason: hard.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}
