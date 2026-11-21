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
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart'
    show ChartId;
import 'package:zaghlol/features/insights/presentation/chart_detail.dart'
    show ChartDetailScreen, chartDetailTitle;
import 'package:zaghlol/features/insights/presentation/charts/locked_chart_card.dart'
    show LockedChartCard;
import 'package:zaghlol/features/settings/debug/debug_sms_diagnostics_screen.dart'
    show DebugSmsDiagnosticsScreen;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/z_button.dart' show ZButton;
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart'
    show ZAddButton, ZBottomBar;
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/explorer.dart';
import 'support/explorer_seed.dart';

// One part per run (a fresh app process each): 0-3 = the four tabs, 4 = the
// Add sheet, -1 = all. A single long run exhausted the app's Java heap.
const _part = int.fromEnvironment('EXPLORER_PART', defaultValue: -1);

// TEST-explorer3: `review` (Arabic) seeds doubtful SMS through the emulator
// modem (device-flows.sh sends them before the run), opens the Review screen
// and taps Keep, Edit, Ignore and show/hide original, then opens the SMS
// diagnostics; `charts` (English) visits all 12 charts (plus the budget bars)
// as a free user.
//
// FU-245: which variant of the run. `ar` (default) is the original Arabic
// light run; `en` English; `dark` the dark theme (Arabic); `scale` Arabic at
// the system text scale 1.3 (device-flows.sh sets `font_scale` first);
// `onboarding` / `onboarding_en` a fresh install walked through the
// first-run flow; `paywall` the Gold paywall (S-68). The variants explore
// two levels deep so that one app process stays within the heap.
const _mode = String.fromEnvironment('EXPLORER_MODE', defaultValue: 'ar');
const _fresh = _mode == 'onboarding' || _mode == 'onboarding_en';

/// Problems found by the TEST-explorer3 flows (charts, review).
final List<String> flowProblems = [];

void _say(String line) {
  // ignore: avoid_print
  print('EXPLORER3 $line');
}

void _check(bool ok, String what) {
  if (!ok) {
    flowProblems.add(what);
    _say('PROBLEM $what');
  }
}

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
      _mode == 'en' || _mode == 'onboarding_en' || _mode == 'charts'
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
    final bar = find.byType(ZBottomBar);
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
            if (_mode == 'charts') {
              await _visitCharts(
                t,
                l10nEn,
                (n) => shot(t, n),
                selectTab,
                goHome,
              );
            } else if (_mode == 'review') {
              await _reviewFlow(t, l10n, (n) => shot(t, n), goHome);
            } else if (_mode == 'paywall') {
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
            final special = _mode == 'charts' || _mode == 'review';
            for (
              var i = 0;
              i < 4 && !ex.timedOut && _mode != 'paywall' && !special;
              i++
            ) {
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
                !special &&
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
      ex.screens.length + (_mode == 'charts' || _mode == 'review' ? 1 : 0),
      greaterThan(_part < 0 && _mode == 'ar' ? 8 : 0),
      reason: 'explored real screens',
    );
    expect(hard, isEmpty, reason: hard.join('\n'));
    expect(flowProblems, isEmpty, reason: flowProblems.join('\n'));
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
    // The primary button can sit below the fold on a small phone.
    await t.ensureVisible(target);
    await settle();
    await t.tap(target);
    await settle();
    await shot('onb-$step');
  }
  for (var i = 0; i < 40 && bar.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  await shot('onb-end');
}

/// Scrolls [f] into view and lays the screen out again: `ensureVisible`
/// alone does not pump, so a following tap would use the old position
/// (batch-32: Keep, built in the list's cache area, was tapped off-screen).
Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await _settleFor(t, 400);
}

Future<void> _settleFor(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// All 12 charts (and the budget bars) as a free user: first the Charts list
/// must hold no locked card, then every chart's detail screen opens with its
/// title, without the locked preview.
Future<void> _visitCharts(
  WidgetTester t,
  AppLocalizations l,
  Future<void> Function(String) shot,
  Future<void> Function(int) selectTab,
  Future<void> Function() goHome,
) async {
  await selectTab(1);
  await _settleFor(t, 1500);
  await shot('charts-list-0');
  var locked = 0;
  for (var i = 0; i < 14; i++) {
    locked += find.byType(LockedChartCard).evaluate().length;
    final sc = find.byType(Scrollable);
    if (sc.evaluate().isEmpty) break;
    await t.drag(sc.last, const Offset(0, -500));
    await _settleFor(t, 400);
    if (i == 3 || i == 7 || i == 11) await shot('charts-list-$i');
  }
  _check(locked == 0, 'free user sees $locked locked chart cards in the list');
  await goHome();
  final nav = rootNavigatorKey.currentState!;
  for (final id in ChartId.values) {
    unawaited(
      nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChartDetailScreen(chart: id, code: 'EGP'),
        ),
      ),
    );
    await _settleFor(t, 1800);
    final title = chartDetailTitle(l, id);
    _check(
      find.text(title).evaluate().isNotEmpty,
      'chart ${id.name}: title missing',
    );
    _check(
      find.text(l.insightsChartDetailLockedTitle).evaluate().isEmpty,
      'chart ${id.name}: locked preview shown to a free user',
    );
    _say('CHART ${id.name} opened');
    await shot('chart-${id.index.toString().padLeft(2, '0')}-${id.name}');
    nav.pop();
    await _settleFor(t, 500);
  }
}

/// The list builds only the cards near the screen: scroll the vertical list
/// (top first, then down) until [f] is built. False if it never is.
Future<bool> _reveal(WidgetTester t, Finder f) async {
  final list = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axis == Axis.vertical,
  );
  if (f.evaluate().isNotEmpty) return true;
  if (list.evaluate().isEmpty) return false;
  for (var i = 0; i < 6; i++) {
    await t.drag(list.first, const Offset(0, 600));
    await _settleFor(t, 150);
  }
  for (var i = 0; i < 16; i++) {
    if (f.evaluate().isNotEmpty) return true;
    await t.drag(list.first, const Offset(0, -350));
    await _settleFor(t, 300);
  }
  return f.evaluate().isNotEmpty;
}

Finder _zbutton(String label) =>
    find.byWidgetPredicate((w) => w is ZButton && w.label == label);

/// Doubtful SMS (sent through the emulator modem before the run) on the
/// Review screen: show/hide original, Keep, Edit, Ignore; then the SMS
/// diagnostics screen.
Future<void> _reviewFlow(
  WidgetTester t,
  AppLocalizations l,
  Future<void> Function(String) shot,
  Future<void> Function() goHome,
) async {
  final ctx = rootNavigatorKey.currentContext!;
  final container = ProviderScope.containerOf(ctx);
  final db = await container.read(appDatabaseProvider.future);
  Future<int> scalar(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  // The SMS sat in the inbox / spool before the app started: read it like
  // the first-run scan does, then give the ingest a moment.
  try {
    final scan = await container.read(inboxScanServiceProvider.future);
    final p = await scan?.startFirstRun();
    _say('SCAN imported=${p?.imported} scanned=${p?.scanned}');
  } on Object catch (e) {
    _say('SCAN_FAILED ${e.runtimeType}');
  }
  for (var i = 0; i < 40; i++) {
    final n = await scalar(
      "SELECT COUNT(*) FROM raw_messages WHERE channel = 'sms'",
    );
    if (n >= 4) break;
    await _settleFor(t, 1000);
  }
  _say(
    'SMS stored=${await scalar("SELECT COUNT(*) FROM raw_messages WHERE channel = 'sms'")} '
    'txns=${await scalar('SELECT COUNT(*) FROM transactions')} '
    'openReview=${await scalar('SELECT COUNT(*) FROM review_items WHERE resolved_at IS NULL')}',
  );

  // The scan above opens the "your cards" results sheet over Home (the
  // app's own behaviour): close it before looking at the Review screen.
  await shot('review-00-after-scan');
  rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  await _settleFor(t, 800);
  GoRouter.of(ctx).go(AppRoutes.review);
  await _settleFor(t, 2500);
  rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  await _settleFor(t, 500);
  await shot('review-0-list');
  final originals = find.byKey(const ValueKey('reviewOriginalText'));
  await _reveal(t, originals);
  final before = originals.evaluate().length;
  _say('REVIEW cards with original text: $before');
  _check(before >= 1, 'Review shows $before cards with original text');

  // Show / hide original.
  if (before > 0) {
    await _scrollTo(t, originals.first);
    await t.tap(originals.first);
    await _settleFor(t, 800);
    _check(
      find.byKey(const ValueKey('reviewOriginalBody')).evaluate().isNotEmpty,
      'Show original did not reveal the text',
    );
    _check(
      find.text(l.ingestionReviewHideOriginal).evaluate().isNotEmpty,
      'the toggle did not change to Hide original',
    );
    await shot('review-1-original-shown');
    await t.tap(originals.first);
    await _settleFor(t, 800);
    _check(
      find.byKey(const ValueKey('reviewOriginalBody')).evaluate().isEmpty,
      'Hide original left the text visible',
    );
  }

  // Keep: the first card whose Keep is enabled.
  final keeps = find.byWidgetPredicate(
    (w) =>
        w is ZButton &&
        w.key == const ValueKey('reviewKeep') &&
        w.onPressed != null,
  );
  await _reveal(t, keeps);
  _say('REVIEW enabled Keep buttons: ${keeps.evaluate().length}');
  _check(keeps.evaluate().isNotEmpty, 'no card offers an enabled Keep');
  if (keeps.evaluate().isNotEmpty) {
    final txns = await scalar('SELECT COUNT(*) FROM transactions');
    await _scrollTo(t, keeps.first);
    await t.tap(keeps.first);
    await _settleFor(t, 1500);
    var after = await scalar('SELECT COUNT(*) FROM transactions');
    for (var i = 0; i < 8 && after == txns; i++) {
      await _settleFor(t, 1000);
      after = await scalar('SELECT COUNT(*) FROM transactions');
    }
    _check(
      after == txns + 1,
      'Keep saved ${after - txns} transactions (want 1)',
    );
    await shot('review-2-after-keep');
  }

  // Edit: opens the Add screen; Back returns to Review.
  final edit = find.byWidgetPredicate(
    (w) =>
        w is ZButton &&
        (w.label == l.commonActionEdit ||
            w.label == l.ingestionReviewUnreadEnter) &&
        w.onPressed != null,
  );
  if (await _reveal(t, edit)) {
    await _scrollTo(t, edit.first);
    await t.tap(edit.first);
    await _settleFor(t, 1500);
    await shot('review-3-edit-add-screen');
    GoRouter.of(rootNavigatorKey.currentContext!).go(AppRoutes.review);
    await _settleFor(t, 1500);
  } else {
    _check(false, 'no Edit button on the Review screen');
  }

  // Ignore (Dismiss).
  final dismiss = _zbutton(l.commonActionDismiss);
  if (await _reveal(t, dismiss)) {
    final open = await scalar(
      'SELECT COUNT(*) FROM review_items WHERE resolved_at IS NULL',
    );
    await _scrollTo(t, dismiss.first);
    await t.tap(dismiss.first);
    await _settleFor(t, 1500);
    // The card leaves at once; the database row closes when the Undo
    // snackbar times out.
    var after = await scalar(
      'SELECT COUNT(*) FROM review_items WHERE resolved_at IS NULL',
    );
    for (var i = 0; i < 10 && after == open; i++) {
      await _settleFor(t, 1000);
      after = await scalar(
        'SELECT COUNT(*) FROM review_items WHERE resolved_at IS NULL',
      );
    }
    _check(after == open - 1, 'Ignore resolved ${open - after} items (want 1)');
    await shot('review-4-after-ignore');
  } else {
    _check(false, 'no Ignore button on the Review screen');
  }

  // SMS diagnostics (dev build).
  unawaited(
    rootNavigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DebugSmsDiagnosticsScreen(),
      ),
    ),
  );
  await _settleFor(t, 2000);
  _check(
    find.byKey(const Key('sms-diag-list')).evaluate().isNotEmpty,
    'SMS diagnostics list not shown',
  );
  final refresh = find.byKey(const Key('sms-diag-refresh'));
  if (refresh.evaluate().isNotEmpty) {
    await t.tap(refresh.first);
    await _settleFor(t, 1000);
  }
  await shot('review-5-sms-diagnostics');
  rootNavigatorKey.currentState!.pop();
  await goHome();
}
