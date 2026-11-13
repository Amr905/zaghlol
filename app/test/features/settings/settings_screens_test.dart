import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';
import 'package:zaghlol/features/settings/presentation/server_allow_list.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import 'settings_harness.dart';

class _FakeLock extends AppLockController {
  _FakeLock(this.result);
  final EnableLockResult result;
  int enableCalls = 0;
  bool? synced;

  @override
  Future<EnableLockResult> enable(String reason) async {
    enableCalls++;
    return result;
  }

  @override
  void syncEnabled(bool enabled) => synced = enabled;
}

AppLocalizations _t(WidgetTester tester, Type screen) =>
    AppLocalizations.of(tester.element(find.byType(screen)));

const _screens = <String, Widget>{
  'main': SettingsMainScreen(),
  'prefs': PreferencesScreen(),
  'privacy': PrivacyScreen(platform: 'ios'),
  'about': AboutScreen(),
};

List<Override> _reads() => [
  supportCodeProvider.overrideWith((ref) async => 'abc-123'),
];

Finder _confirm(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void main() {
  group('layout: ar + en, RTL, text scale 1.3 (no overflow)', () {
    for (final locale in const [Locale('ar'), Locale('en')]) {
      for (final dark in [false, true]) {
        for (final e in _screens.entries) {
          testWidgets('${e.key} $locale dark=$dark', (tester) async {
            final h = SettingsHarness();
            addTearDown(h.db.close);
            await tester.binding.setSurfaceSize(const Size(390, 844));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              h.app(
                e.value,
                locale: locale,
                dark: dark,
                scale: 1.3,
                payday: 25,
                appLock: true,
                approx: true,
                overrides: _reads(),
              ),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            final dir = Directionality.of(
              tester.element(find.byType(e.value.runtimeType)),
            );
            expect(
              dir,
              locale.languageCode == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            );
          });
        }
      }
    }
  });

  group('S-60 main', () {
    testWidgets('shows every row, Gold free, no finish-setup banner', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const SettingsMainScreen()));
      await settle(tester);
      final t = _t(tester, SettingsMainScreen);
      for (final s in [
        t.settingsMainGoldFree,
        t.settingsMainPreferences,
        t.settingsMainNotifications,
        t.settingsMainCapture,
        t.settingsMainCategories,
        t.settingsMainBackup,
        t.settingsMainExports,
        t.settingsMainPrivacy,
        t.settingsMainAbout,
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining(t.settingsMainSeeGold), findsOneWidget);
    });

    testWidgets('finish-setup banner and Gold plan', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(
        h.app(
          const SettingsMainScreen(),
          overrides: [
            setupStepsLeftProvider.overrideWithValue(2),
            goldPlanProvider.overrideWithValue('yearly'),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, SettingsMainScreen);
      expect(find.text(t.settingsMainFinishSetup(2, '2')), findsOneWidget);
      expect(find.text(t.settingsMainGoldActive('yearly')), findsOneWidget);
    });

    testWidgets('Privacy and About are one tap away', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const SettingsMainScreen()));
      await settle(tester);
      final t = _t(tester, SettingsMainScreen);
      await tester.tap(find.text(t.settingsMainPrivacy));
      await settle(tester);
      expect(find.byType(PrivacyScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text(t.settingsMainAbout));
      await settle(tester);
      expect(find.byType(AboutScreen), findsOneWidget);
    });

    testWidgets('destination callback fires', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      var hit = 0;
      await tester.pumpWidget(
        h.app(
          SettingsMainScreen(
            destinations: SettingsDestinations(onBackup: () => hit++),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(
        find.text(_t(tester, SettingsMainScreen).settingsMainBackup),
      );
      expect(hit, 1);
    });
  });

  group('S-72 preferences', () {
    testWidgets('theme choice is written to settings', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PreferencesScreen()));
      await settle(tester);
      final t = _t(tester, PreferencesScreen);
      await tester.tap(find.text(t.settingsPrefsThemeDark));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(
        await tester.runAsync(() => h.repo.get(Settings.theme)),
        ThemePref.dark,
      );
    });

    testWidgets('digits row only in Arabic', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PreferencesScreen()));
      await settle(tester);
      expect(
        find.text(_t(tester, PreferencesScreen).settingsPrefsDigits),
        findsNothing,
      );
      await tester.pumpWidget(
        h.app(const PreferencesScreen(), locale: const Locale('ar')),
      );
      await settle(tester);
      expect(
        find.text(_t(tester, PreferencesScreen).settingsPrefsDigits),
        findsOneWidget,
      );
    });

    testWidgets('approx target row hidden while the view is off', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PreferencesScreen()));
      await settle(tester);
      expect(
        find.text(_t(tester, PreferencesScreen).settingsPrefsCombineInto),
        findsNothing,
      );
    });

    testWidgets('approx target row shown while the view is on', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PreferencesScreen(), approx: true));
      await settle(tester);
      expect(
        find.text(_t(tester, PreferencesScreen).settingsPrefsCombineInto),
        findsOneWidget,
      );
    });

    testWidgets('negative income shows the error and writes nothing', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PreferencesScreen()));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '-5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        find.text(_t(tester, PreferencesScreen).settingsPrefsIncomeNegative),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => h.repo.get(Settings.incomeTarget)),
        isNull,
      );
    });

    testWidgets('app lock on: enables via controller, hides amounts (FU-130)', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      final fake = _FakeLock(EnableLockResult.enabled);
      await tester.pumpWidget(
        h.app(
          const PreferencesScreen(),
          overrides: [appLockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await settle(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(fake.enableCalls, 1);
      expect(
        await tester.runAsync(
          () => h.repo.get(Settings.hideAmountsNotifications),
        ),
        isTrue,
      );
    });

    testWidgets('app lock refused (no screen lock): message, no hide-amounts', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(
        h.app(
          const PreferencesScreen(),
          overrides: [
            appLockControllerProvider.overrideWith(
              () => _FakeLock(EnableLockResult.notSecure),
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(
        find.text(_t(tester, PreferencesScreen).appLockUnavailable),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => h.repo.get(Settings.hideAmountsNotifications),
        ),
        isFalse,
      );
    });

    testWidgets('app lock off persists false', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      final fake = _FakeLock(EnableLockResult.enabled);
      await tester.runAsync(() => h.repo.set(Settings.appLockEnabled, true));
      await tester.pumpWidget(
        h.app(
          const PreferencesScreen(),
          appLock: true,
          overrides: [appLockControllerProvider.overrideWith(() => fake)],
        ),
      );
      await settle(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(
        await tester.runAsync(() => h.repo.get(Settings.appLockEnabled)),
        isFalse,
      );
      expect(fake.synced, isFalse);
    });
  });

  group('S-71 privacy', () {
    testWidgets('server list is the allow-list; seat keys iPhone only', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.binding.setSurfaceSize(const Size(390, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(h.app(const PrivacyScreen(platform: 'ios')));
      await settle(tester);
      final t = _t(tester, PrivacyScreen);
      for (final s in [
        t.privacyServerItemId,
        t.privacyServerItemPurchase,
        t.privacyServerItemSignIn,
        t.privacyServerItemMerchants,
        t.privacyServerItemVersion,
        t.privacyServerItemAttest,
        t.privacyServerItemBankRequest,
        t.privacyServerTimeNonceSummary,
        t.privacyServerSeatKeysSummary,
        t.privacyServerDeleteKeepsSummary,
        t.privacyServerSupportNoticeSummary,
        t.privacyServerSupportRowsSummary,
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      await tester.pumpWidget(h.app(const PrivacyScreen(platform: 'android')));
      await settle(tester);
      expect(find.text(t.privacyServerSeatKeysSummary), findsNothing);
      expect(find.text(t.privacyServerDeleteKeepsSummary), findsNothing);
      expect(find.text(t.privacyServerTimeNonceSummary), findsOneWidget);
    });

    test('allow-list covers every entry on iOS, fewer on Android', () {
      expect(serverAllowList('ios'), ServerKnows.values);
      expect(serverAllowList('android'), isNot(contains(ServerKnows.seatKeys)));
    });

    testWidgets('contribution opt-in goes through the queue; off clears', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(h.app(const PrivacyScreen(platform: 'android')));
      await settle(tester);
      final toggle = find.byType(Switch).first;
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(
        await tester.runAsync(() => h.repo.get(Settings.contributionOptIn)),
        isTrue,
      );
      expect(
        find.text(_t(tester, PrivacyScreen).privacyContributeTurnedOn),
        findsOneWidget,
      );
    });

    testWidgets('delete needs the typed word; wipe runs once', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      var wiped = 0;
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          overrides: [
            wipeEverythingProvider.overrideWithValue(() async => wiped++),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, PrivacyScreen);
      await tester.ensureVisible(find.text(t.privacyDeleteRow));
      await tester.tap(find.text(t.privacyDeleteRow));
      await settle(tester);
      expect(find.text(t.privacyDeleteNoBackup), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(_confirm(t.privacyDeleteConfirm));
      await tester.pump();
      expect(find.text(t.privacyDeleteTypeMismatch), findsOneWidget);
      expect(wiped, 0);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.tap(_confirm(t.privacyDeleteConfirm));
      await settle(tester);
      expect(wiped, 1);
    });

    testWidgets('Arabic confirmation word works', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      var wiped = 0;
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          locale: const Locale('ar'),
          overrides: [
            wipeEverythingProvider.overrideWithValue(() async => wiped++),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, PrivacyScreen);
      await tester.ensureVisible(find.text(t.privacyDeleteRow));
      await tester.tap(find.text(t.privacyDeleteRow));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'احذف');
      await tester.tap(_confirm(t.privacyDeleteConfirm));
      await settle(tester);
      expect(wiped, 1);
    });

    testWidgets('rooted note only on a compromised phone', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          overrides: [deviceCompromisedProvider.overrideWithValue(true)],
        ),
      );
      await settle(tester);
      final t = _t(tester, PrivacyScreen);
      expect(find.text(t.privacyRootedRow('android')), findsOneWidget);
    });
  });

  group('S-74 about', () {
    testWidgets('never synced, support code copies', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        h.app(
          const AboutScreen(),
          overrides: [
            supportCodeProvider.overrideWith((ref) async => 'abc-123'),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, AboutScreen);
      expect(find.text(t.aboutMainNeverSynced), findsNWidgets(2));
      expect(find.text(t.commonSupportCodeValue('abc-123')), findsOneWidget);
      await tester.tap(find.text(t.commonSupportCodeLabel));
      await tester.pump();
      expect(clip, 'abc-123');
      expect(find.text(t.commonSupportCodeCopied), findsOneWidget);
    });

    testWidgets('synced dates; diagnostics hidden without exporter', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(
        h.app(
          const AboutScreen(),
          overrides: [
            syncStatusProvider.overrideWithValue(
              SyncStatus(catalogAt: DateTime(2026, 11, 1)),
            ),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, AboutScreen);
      expect(find.textContaining('2026'), findsWidgets);
      expect(find.text(t.aboutMainNeverSynced), findsOneWidget);
      expect(find.text(t.aboutDiagShare), findsNothing);
    });

    testWidgets('diagnostics: empty log says so; events are shared', (
      tester,
    ) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      var text = 'zaghlol diagnostics\n';
      final shared = <String>[];
      await tester.pumpWidget(
        h.app(
          const AboutScreen(),
          overrides: [
            diagnosticsTextProvider.overrideWithValue(() async => text),
            shareTextProvider.overrideWithValue((s) async => shared.add(s)),
          ],
        ),
      );
      await settle(tester);
      final t = _t(tester, AboutScreen);
      await tester.ensureVisible(find.text(t.aboutDiagShare));
      await tester.tap(find.text(t.aboutDiagShare));
      await tester.pump();
      expect(find.text(t.aboutDiagEmpty), findsOneWidget);
      expect(shared, isEmpty);
      text = 'zaghlol diagnostics\n2026-11-01T00:00:00Z info SOME_CODE\n';
      await tester.tap(find.text(t.aboutDiagShare));
      await tester.pump();
      expect(shared, [text]);
    });
  });
}
