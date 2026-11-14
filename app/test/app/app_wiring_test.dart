// WIRE-NAV: every entry point opens its screen. The screens are replaced by
// marker pages through `appScreensProvider`; the wiring itself is real.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;
import 'package:zaghlol/app/app_config.dart';
import 'package:zaghlol/app/app_navigation.dart';
import 'package:zaghlol/app/app_screens.dart';
import 'package:zaghlol/app/onboarding_gate.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/features/accounts/presentation/money_tab.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/presentation/gold_ui_ports.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/onboarding/presentation/android_setup.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';

import '../features/settings/settings_harness.dart';

final _account = Account(
  id: 'a1',
  kind: AccountKind.debit,
  label: 'Test card',
  defaultCurrency: Currency.of('EGP'),
  isHidden: false,
  isDefaultCash: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// A marker page: text `stub:<name>` plus one button per action.
Widget _marker(String name, [Map<String, VoidCallback> actions = const {}]) =>
    Scaffold(
      body: Column(
        children: [
          Text('stub:$name'),
          for (final e in actions.entries)
            TextButton(
              key: ValueKey('${name}__${e.key}'),
              onPressed: e.value,
              child: Text('${name}__${e.key}'),
            ),
        ],
      ),
    );

class _Rec {
  final calls = <String>[];
  SettingsDestinations? settingsDestinations;
  VoidCallback? onTransactionsFromCard;
  void Function(Account)? onSaved;
}

AppScreens _stubs(_Rec r) {
  Future<void> page(
    BuildContext c,
    String name, [
    Map<String, VoidCallback> actions = const {},
  ]) {
    r.calls.add(name);
    return pushScreen<void>(c, (_) => _marker(name, actions));
  }

  return AppScreens(
    cardDetail: (c, a, {onOpenTransactions, onOpenTransaction}) =>
        page(c, 'cardDetail'),
    compareCards: (c, {onOpenTransactions}) => page(c, 'compare'),
    startAddCard: (c, {onSaved, onOpenExisting}) {
      r.onSaved = onSaved;
      return page(c, 'startAddCard');
    },
    editCard: (c, a, {onOpenCapture}) =>
        page(c, 'editCard', {'capture': () => onOpenCapture!(a)}),
    cardCaptureSheet: (c, a) => page(c, 'cardCapture'),
    addAsset: (c) => page(c, 'addAsset'),
    prices: (c) => page(c, 'prices'),
    paywall: (c) => page(c, 'paywall'),
    settings: (c, d) {
      r.settingsDestinations = d;
      return page(c, 'settings');
    },
    backup: (c, {required onOpenRestore, required iCloud}) =>
        page(c, 'backup', {'restore': onOpenRestore}),
    restore:
        (
          c, {
          required onRestored,
          required onStartFresh,
          required onUpdateApp,
          required iCloud,
        }) => page(c, 'restore', {
          'restored': () => onRestored(regrantDue: false),
          'fresh': onStartFresh,
          'update': onUpdateApp,
        }),
    captureSettings: (c, {required goldActive, required onOpenTemplates}) =>
        page(c, goldActive ? 'captureGold' : 'captureFree', {
          'templates': onOpenTemplates,
        }),
    templateBuilder: (c) => page(c, 'templateBuilder'),
    categories: (c) => page(c, 'categories'),
    privacy: (c) => page(c, 'privacy'),
    budget: (c, {required onCategoryTap}) => page(c, 'budget'),
    ask: (c) => _marker('ask'),
    review: (c) => _marker('review'),
    transactions: (c, {required onOpenTransaction}) =>
        _marker('transactions', {'open': () => onOpenTransaction('t1')}),
    transactionDetail: (
      c,
      id, {
      required onSplit,
      required onLinkTransfer,
      required onMoneyBackFor,
    }) => page(c, 'txnDetail'),
    androidSetup: ({required onDone, required onSkipped}) => _marker(
      'androidSetup',
      {'done': onDone, 'skipSms': () => onSkipped(kSetupStepSms)},
    ),
    scanResults:
        ({
          required onDone,
          required onOpenReview,
          required onEditCard,
          required onSetupCredit,
        }) => _marker('scanResults', {
          'done': onDone,
          'review': onOpenReview,
          'edit': () => onEditCard('a1'),
        }),
    scanResultsSheet: (
      c, {
      required onDone,
      required onOpenReview,
      required onEditCard,
      required onSetupCredit,
    }) => page(c, 'scanResultsSheet'),
  );
}

void main() {
  for (final lang in ['ar', 'en']) {
    final locale = Locale(lang);
    group('wiring ($lang)', () {
      late SettingsHarness h;
      late _Rec rec;
      late List<Uri> opened;

      setUp(() {
        h = SettingsHarness();
        rec = _Rec();
        opened = [];
      });
      tearDown(() => h.db.close());

      /// Pumps a host whose body is [build] of its context; the screens are
      /// stubs.
      Future<BuildContext> host(
        WidgetTester tester, {
        void Function(BuildContext)? build,
      }) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          h.app(
            Builder(
              builder: (c) {
                build?.call(c);
                return const SizedBox(key: ValueKey('host'));
              },
            ),
            locale: locale,
            scale: 1.3,
            overrides: [
              appScreensProvider.overrideWithValue(_stubs(rec)),
              externalUrlOpenerProvider.overrideWithValue(
                (u) async => opened.add(u),
              ),
            ],
          ),
        );
        await tester.pump();
        return tester.element(find.byKey(const ValueKey('host')));
      }

      Future<void> pop(WidgetTester t) async {
        Navigator.of(
          t.element(find.byKey(const ValueKey('host'), skipOffstage: false)),
        ).pop();
        await t.pumpAndSettle();
      }

      Future<void> expectOpened(WidgetTester tester, String name) async {
        await tester.pumpAndSettle();
        expect(find.text('stub:$name'), findsOneWidget, reason: name);
      }

      testWidgets('Money tab: every callback opens its screen', (t) async {
        late MoneyTab tab;
        final ctx = await host(
          t,
          build: (c) => tab = wiredTabRoots.money(c) as MoneyTab,
        );
        expect(ctx, isNotNull);
        Future<void> back() => pop(t);

        tab.onOpenAccount!(_account);
        await expectOpened(t, 'cardDetail');
        await back();
        tab.onCompare!();
        await expectOpened(t, 'compare');
        await back();
        tab.onAdd!();
        await expectOpened(t, 'startAddCard');
        // A saved card opens its S-41.
        rec.onSaved!(_account);
        await t.pumpAndSettle();
        expect(find.text('stub:cardDetail'), findsOneWidget);
        await back();
        await back();
        tab.onOpenAssetsPaywall!();
        await expectOpened(t, 'paywall');
        await back();
        tab.onAddAsset!();
        await expectOpened(t, 'addAsset');
        await back();
        tab.onOpenPrices!();
        await expectOpened(t, 'prices');
      });

      testWidgets('Home: settings, budget, detail, backup, finish setup', (
        t,
      ) async {
        late HomeScreen home;
        await host(t, build: (c) => home = wiredTabRoots.home(c) as HomeScreen);
        final a = home.actions!;
        expect(a.openSettings, isNotNull);
        expect(a.openTransactions, isNotNull);
        expect(a.openSpentTransactions, isNotNull);
        a.openSettings!();
        await expectOpened(t, 'settings');
        expect(rec.settingsDestinations!.onGold, isNotNull);
        await pop(t);
        a.openBudget!();
        await expectOpened(t, 'budget');
        await pop(t);
        a.openSetBudget!();
        await expectOpened(t, 'budget');
        await pop(t);
        a.openTransaction!('t1');
        await expectOpened(t, 'txnDetail');
        await pop(t);
        a.openBackup!();
        await expectOpened(t, 'backup');
        await pop(t);
        a.openFinishSetup!();
        // Android: S-02 (the default test platform).
        await t.pumpAndSettle();
        expect(find.text('stub:androidSetup'), findsOneWidget);
      });

      testWidgets('Settings rows: Gold, capture, categories, backup', (
        t,
      ) async {
        late SettingsDestinations d;
        final ctx = await host(t);
        d = settingsDestinations(ctx);
        d.onGold!();
        await expectOpened(t, 'paywall');
        await pop(t);
        d.onCategories!();
        await expectOpened(t, 'categories');
        await pop(t);
        d.onBackup!();
        await expectOpened(t, 'backup');
        // S-66 -> S-04 -> store link.
        await t.tap(find.byKey(const ValueKey('backup__restore')));
        await expectOpened(t, 'restore');
        await t.tap(find.byKey(const ValueKey('restore__update')));
        await t.pump();
        expect(opened, [Uri.parse(AppLinks.storePage)]);
        await t.tap(find.byKey(const ValueKey('restore__restored')));
        await t.pumpAndSettle();
        expect(find.text('stub:backup'), findsNothing);
      });

      testWidgets('Capture settings: Free templates meet the paywall, Gold '
          'opens the builder', (t) async {
        final ctx = await host(t);
        settingsDestinations(ctx).onCapture!();
        await expectOpened(t, 'captureFree');
        await t.tap(find.byKey(const ValueKey('captureFree__templates')));
        await expectOpened(t, 'paywall');
        Navigator.of(t.element(find.text('stub:paywall'))).pop();
        await pop(t);

        ProviderScope.containerOf(ctx)
            .read(entitlementStateProvider.notifier)
            .applyVerified(verified: true, status: 'active');
        settingsDestinations(ctx).onCapture!();
        await expectOpened(t, 'captureGold');
        await t.tap(find.byKey(const ValueKey('captureGold__templates')));
        await expectOpened(t, 'templateBuilder');
      });

      testWidgets('card row of the cards chart and Gold openers are wired', (
        t,
      ) async {
        final c = ProviderScope.containerOf(await host(t));
        expect(c.read(chartCardOpenerProvider), isNull);
        final wired = ProviderContainer(
          overrides: [...navigationWiringOverrides(rootNavigatorKey)].cast(),
        );
        addTearDown(wired.dispose);
        expect(wired.read(chartCardOpenerProvider), isNotNull);
        expect(wired.read(goldSignInOpenerProvider), isNotNull);
        wired.read(goldLinkOpenerProvider)(GoldLink.terms);
      });

      testWidgets('router routes: review, transactions and the Ask tab', (
        t,
      ) async {
        final roots = TabRoots(
          zaghlol: wiredTabRoots.zaghlol,
          review: wiredTabRoots.review,
          transactions: wiredTabRoots.transactions,
        );
        final router = buildAppRouter(roots);
        addTearDown(router.dispose);
        await t.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          ProviderScope(
            overrides: [appScreensProvider.overrideWithValue(_stubs(rec))],
            child: MaterialApp.router(
              theme: ZaghlolTheme.light,
              locale: locale,
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await t.pumpAndSettle();
        router.go('/zaghlol');
        await expectOpened(t, 'ask');
        router.go('/home/review');
        await expectOpened(t, 'review');
        router.go('/home/transactions');
        await expectOpened(t, 'transactions');
        await t.tap(find.byKey(const ValueKey('transactions__open')));
        await expectOpened(t, 'txnDetail');
      });

      testWidgets('first run: Welcome -> setup -> scan results -> app', (
        t,
      ) async {
        await t.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          h.app(
            const OnboardingGate(child: Text('shell')),
            locale: locale,
            overrides: [appScreensProvider.overrideWithValue(_stubs(rec))],
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('shell'), findsNothing);
        await t.tap(find.byKey(const ValueKey('welcome-start')));
        await expectOpened(t, 'androidSetup');
        await t.tap(find.byKey(const ValueKey('androidSetup__done')));
        await expectOpened(t, 'scanResults');
        await t.tap(find.byKey(const ValueKey('scanResults__done')));
        await t.pumpAndSettle();
        expect(find.text('shell'), findsOneWidget);
        expect(await h.repo.get(Settings.setupInstalledOn), isNotNull);
      });

      testWidgets('first run: scan results open the review queue and the '
          'card editor', (t) async {
        await t.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          h.app(
            const OnboardingGate(child: Text('shell')),
            locale: locale,
            overrides: [
              appScreensProvider.overrideWithValue(_stubs(rec)),
              accountsRepositoryProvider.overrideWith(
                (ref) async => _OneAccountRepo(),
              ),
            ],
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('welcome-start')));
        await expectOpened(t, 'androidSetup');
        await t.tap(find.byKey(const ValueKey('androidSetup__done')));
        await expectOpened(t, 'scanResults');
        await t.tap(find.byKey(const ValueKey('scanResults__edit')));
        await expectOpened(t, 'editCard');
        // The editor's capture row opens S-62.
        await t.tap(find.byKey(const ValueKey('editCard__capture')));
        await expectOpened(t, 'cardCapture');
        for (final name in ['cardCapture', 'editCard']) {
          Navigator.of(t.element(find.text('stub:$name'))).pop();
          await t.pumpAndSettle();
        }
        await t.tap(find.byKey(const ValueKey('scanResults__review')));
        await t.pumpAndSettle();
        expect(find.text('shell'), findsOneWidget);
        expect(await h.repo.get(Settings.setupInstalledOn), isNotNull);
      });

      testWidgets('first run: skipping the SMS step is recorded for '
          '"Finish setup"', (t) async {
        await t.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          h.app(
            const OnboardingGate(child: Text('shell')),
            locale: locale,
            overrides: [appScreensProvider.overrideWithValue(_stubs(rec))],
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('welcome-start')));
        await expectOpened(t, 'androidSetup');
        await t.tap(find.byKey(const ValueKey('androidSetup__skipSms')));
        await t.pumpAndSettle();
        expect(find.text('shell'), findsOneWidget);
        expect(await h.repo.get(Settings.setupProgress), {'skip_sms'});
      });

      testWidgets('first run: "I already use Zaghlol" opens the restore flow', (
        t,
      ) async {
        await t.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          h.app(
            const OnboardingGate(child: Text('shell')),
            locale: locale,
            overrides: [
              appScreensProvider.overrideWithValue(_stubs(rec)),
              externalUrlOpenerProvider.overrideWithValue(
                (u) async => opened.add(u),
              ),
            ],
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('welcome-restore')));
        await expectOpened(t, 'restore');
        await t.tap(find.byKey(const ValueKey('restore__update')));
        await t.pump();
        expect(opened.single.toString(), AppLinks.storePage);
        // "Start fresh" returns to Welcome.
        await t.tap(find.byKey(const ValueKey('restore__fresh')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('welcome-start')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('welcome-restore')));
        await expectOpened(t, 'restore');
        await t.tap(find.byKey(const ValueKey('restore__restored')));
        await t.pumpAndSettle();
        expect(find.text('shell'), findsOneWidget);
      });

      testWidgets('returning user goes straight to the app', (t) async {
        await h.repo.set(Settings.setupInstalledOn, 20000);
        await t.pumpWidget(
          h.app(
            const OnboardingGate(child: Text('shell')),
            locale: locale,
            overrides: [appScreensProvider.overrideWithValue(_stubs(rec))],
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('shell'), findsOneWidget);
      });

      testWidgets('the scan finishing after Home shows the results sheet', (
        t,
      ) async {
        final scan = _FakeScan();
        addTearDown(scan.close);
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              appScreensProvider.overrideWithValue(_stubs(rec)),
              setupScanProvider.overrideWith((ref) async => scan),
            ],
            child: MaterialApp(
              navigatorKey: rootNavigatorKey,
              locale: locale,
              home: const ScanResultsSheetTrigger(child: Text('home')),
            ),
          ),
        );
        await t.pumpAndSettle();
        scan.emit(const ScanProgress(phase: ScanPhase.running));
        await t.pump();
        expect(rec.calls, isEmpty);
        scan.emit(const ScanProgress(phase: ScanPhase.done, imported: 3));
        await expectOpened(t, 'scanResultsSheet');
        // Shown once.
        scan.emit(const ScanProgress(phase: ScanPhase.done, imported: 3));
        await t.pump();
        expect(rec.calls.where((c) => c == 'scanResultsSheet'), hasLength(1));
      });
    });
  }
}

class _FakeScan implements SetupScan {
  final _c = StreamController<ScanProgress>.broadcast();
  ScanProgress _cur = const ScanProgress();
  void emit(ScanProgress p) {
    _cur = p;
    _c.add(p);
  }

  void close() => unawaited(_c.close());

  @override
  ScanProgress get current => _cur;
  @override
  Stream<ScanProgress> get progress => _c.stream;
  @override
  Future<void> start() async {}
}

class _OneAccountRepo implements AccountsRepository {
  @override
  Future<Account?> byId(String id) async => _account;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
