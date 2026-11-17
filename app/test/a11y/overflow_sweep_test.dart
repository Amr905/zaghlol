// FU-218: text-scale 1.3 overflow sweep. Every main screen is pumped in ar and
// en at 1.3x, then the surface is resized to 360x640 and 320x640 (and a tall
// 360/320 surface for scrolling lists, which build lazily) and the test fails
// on any RenderFlex overflow or other framework exception. Widget tests, not
// PNG goldens.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_screen.dart';
import 'package:zaghlol/features/capture/presentation/capture_settings_screen.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';
import 'package:zaghlol/features/categorization/data/rules_providers.dart';
import 'package:zaghlol/features/categorization/presentation/categories_rules_screen.dart';
import 'package:zaghlol/features/categorization/presentation/category_edit_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';
import 'package:zaghlol/features/recurring/presentation/bill_edit_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bills_screen.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import '../core/ui/shell/shell_harness.dart' as shell;
import '../features/accounts/presentation/card_detail_test.dart' as detail;
import '../features/ask/presentation/ask_screen_test.dart' as ask;
import '../features/capture/presentation/capture_ui_support.dart' as cap;
import '../features/categorization/presentation/categories_screens_test.dart'
    show FakeAdmin, FakeRules, bills, food, sub, rule;
import '../features/gold/presentation/gold_ui_harness.dart';
import '../features/home/presentation/home_harness.dart' as home;
import '../features/ingestion/presentation/review/review_harness.dart' as rev;
import '../features/money/money_tab_test.dart' as money;
import '../features/onboarding/presentation/android_setup_test.dart' as android;
import '../features/onboarding/presentation/android_setup_test.dart'
    show FakeHost, FakeScan;
import '../features/onboarding/presentation/scan_results_test.dart' as scan;
import '../features/insights/presentation/charts/charts_test_support.dart';
import '../features/recurring/presentation/bills_screen_test.dart' show full;
import '../features/settings/settings_harness.dart';
import '../features/transactions/presentation/detail_edit_harness.dart';
import '../features/transactions/presentation/list/list_harness.dart';
import '../support/golden_matrix.dart';
import '../support/ios_setup_host.dart';
import 'a11y_pumps.dart';

typedef _Pump = Future<void> Function(WidgetTester t, GoldenVariant v);

class _Case {
  const _Case(this.pump, {this.tallHeight});
  final _Pump pump;

  /// Also run on a tall surface (scrolling lists build their rows lazily).
  final double? tallHeight;
}

Future<void> _settings(WidgetTester t, GoldenVariant v, Widget screen) async {
  final h = SettingsHarness();
  addTearDown(h.db.close);
  await t.pumpWidget(
    h.app(
      screen,
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
      payday: 25,
      appLock: true,
      overrides: [
        supportCodeProvider.overrideWith((ref) async => 'abc-123'),
        categoriesAdminProvider.overrideWith(
          (ref) async => FakeAdmin([food, bills, sub]),
        ),
        rulesRepositoryProvider.overrideWith((ref) async => FakeRules([rule])),
      ],
    ),
  );
  await settle(t, height: 1400);
}

Future<void> _wrap(
  WidgetTester t,
  GoldenVariant v,
  Widget screen, {
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  await t.pumpWidget(
    harness(
      screen,
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
      overrides: overrides,
    ),
  );
  settle ? await t.pumpAndSettle() : await t.pump();
}

final _cases = <String, _Case>{
  'home': _Case(
    (t, v) => home.pumpHome(
      t,
      platform: TargetPlatform.android,
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
      value: home.model(review: 3),
    ),
    tallHeight: 2400,
  ),
  'home empty': _Case(
    (t, v) => home.pumpHome(
      t,
      platform: TargetPlatform.android,
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
      value: home.model(currencies: [], recent: []),
    ),
  ),
  'money tab': _Case(money.pumpForGolden, tallHeight: 2400),
  'insights shell': _Case(pumpInsightsShell),
  'charts (free)': _Case(
    (t, v) => _wrap(t, v, const ChartsScreen(), overrides: chartOverrides()),
    tallHeight: 6000,
  ),
  'charts (gold, all 12)': _Case((t, v) async {
    await _wrap(
      t,
      v,
      const ChartsScreen(),
      overrides: [...chartOverrides(), ...goldChartOverrides()],
      settle: false,
    );
    ProviderScope.containerOf(t.element(find.byType(ChartsScreen)))
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    await t.pumpAndSettle();
  }, tallHeight: 7000),
  for (final c in ChartId.values)
    'chart detail ${c.name}': _Case(
      (t, v) => _wrap(
        t,
        v,
        ChartDetailScreen(chart: c, code: 'EGP'),
        overrides: [...chartOverrides(), ...goldChartOverrides()],
      ),
      tallHeight: 2000,
    ),
  'zaghlol tab (ask)': _Case(
    (t, v) => ask.pump(
      t,
      ask.FakeEngine((_, _) async => ask.compare()),
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
    ),
  ),
  'add sheet': _Case((t, v) async {
    final router = await shell.pumpShell(
      t,
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
    );
    unawaited(router.push<void>(AppRoutes.addOverHome));
    await t.pumpAndSettle();
  }),
  'app shell (bottom nav)': _Case(
    (t, v) => shell.pumpShell(
      t,
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
    ),
  ),
  'transactions list': _Case(
    (t, v) => pumpList(
      t,
      Harness(
        FakeRepo([
          txnRec('a', merchant: 'Carrefour', minor: 45000),
          txnRec('b', merchant: 'Talabat', minor: 28500),
        ]),
      ),
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
    ),
  ),
  'transaction detail': _Case(
    (t, v) => pumpDetail(
      t,
      Harness(FakeRepo([txnRec('a')])),
      detail: AsyncData(
        detailOf(txnRec('a'), raw: 'SYNTHETIC BANK: purchase 450.00 EGP'),
      ),
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
    ),
    tallHeight: 1600,
  ),
  'transaction editor': _Case(
    (t, v) => pumpEditor(
      t,
      FakeEditor(),
      existing: txnRec('a'),
      locale: v.locale,
      dark: v.dark,
      textScale: v.textScale,
    ),
    tallHeight: 1600,
  ),
  'review queue': _Case(
    (t, v) => rev.pumpReview(
      t,
      rev.reviewApp(
        actions: rev.FakeActions(),
        queue: rev.sampleCards,
        locale: v.locale,
        dark: v.dark,
        scale: v.textScale,
      ),
      size: const Size(390, 1500),
    ),
    tallHeight: 2000,
  ),
  'budgets': _Case(
    (t, v) => _wrap(
      t,
      v,
      const BudgetScreen(),
      overrides: [
        budgetScreenDataProvider.overrideWith(
          (ref) async => data([egpView(), usdView()]),
        ),
      ],
      settle: false,
    ),
    tallHeight: 2000,
  ),
  'edit budgets': _Case(pumpEditBudgets),
  'bills': _Case(
    (t, v) => _wrap(
      t,
      v,
      const BillsScreen(),
      overrides: [billsDataProvider.overrideWith((ref) async => full())],
    ),
    tallHeight: 2000,
  ),
  'bill edit': _Case(
    (t, v) => _wrap(
      t,
      v,
      const BillEditScreen(),
      overrides: [billsDataProvider.overrideWith((ref) async => full())],
    ),
    tallHeight: 2000,
  ),
  'account S-69': _Case(pumpAccountS69),
  'card detail': _Case(
    (t, v) => detail.pumpDetail(
      t,
      overrides: detail.detailOverrides(),
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
    ),
    tallHeight: 2000,
  ),
  'card capture sheet': _Case(pumpCardCaptureSheet),
  'home card filter sheet': _Case(pumpHomeCardFilterSheet),
  'capture settings': _Case((t, v) async {
    await t.pumpWidget(
      cap.host(
        const CaptureSettingsScreen(),
        controls: cap.FakeControls(
          rules: [
            cap.rule('1', 'cib', '9910', 'sms'),
            cap.rule('3', 'revolut', null, 'notification'),
          ],
        ),
        locale: v.locale,
        dark: v.dark,
        scale: v.textScale,
      ),
    );
    await t.pumpAndSettle();
  }, tallHeight: 1600),
  'settings main': _Case(
    (t, v) => _settings(t, v, const SettingsMainScreen()),
    tallHeight: 1800,
  ),
  'settings preferences': _Case(
    (t, v) => _settings(t, v, const PreferencesScreen()),
    tallHeight: 1800,
  ),
  'settings privacy': _Case(
    (t, v) => _settings(t, v, const PrivacyScreen(platform: 'ios')),
    tallHeight: 2400,
  ),
  'settings about': _Case(
    (t, v) => _settings(t, v, const AboutScreen()),
    tallHeight: 1800,
  ),
  'categories and rules': _Case(
    (t, v) => _settings(t, v, const CategoriesRulesScreen()),
    tallHeight: 1800,
  ),
  'category edit': _Case(
    (t, v) => _settings(t, v, const CategoryEditScreen(categoryId: 'sub1')),
    tallHeight: 1800,
  ),
  'paywall': _Case(
    (t, v) => pumpGold(
      t,
      goldApp(
        const PaywallScreen(),
        overrides: goldOverrides(FakeGoldActions()),
        lang: v.locale.languageCode,
        dark: v.dark,
        scale: v.textScale,
      ),
      height: 1400,
    ),
    tallHeight: 2400,
  ),
  'onboarding welcome': _Case(
    (t, v) => _wrap(
      t,
      v,
      WelcomeScreen(onStart: () {}, onRestore: () {}, onPrivacy: () {}),
    ),
    tallHeight: 1200,
  ),
  'onboarding android setup': _Case((t, v) async {
    await t.pumpWidget(
      android.host(
        FakeHost(),
        FakeScan(),
        v.locale.languageCode,
        scale: v.textScale,
      ),
    );
    await t.pump(const Duration(milliseconds: 200));
  }, tallHeight: 1600),
  'onboarding ios setup': _Case((t, v) async {
    await t.pumpWidget(
      iosSetupHost(v.locale.languageCode, scale: v.textScale, dark: v.dark),
    );
    await t.pumpAndSettle();
  }, tallHeight: 1600),
  'onboarding scan results': _Case((t, v) async {
    await t.pumpWidget(
      scan.host(
        const AsyncData(scan.sample),
        v.locale.languageCode,
        dark: v.dark,
        scale: v.textScale,
      ),
    );
    await t.pumpAndSettle();
  }, tallHeight: 1600),
  'lock': _Case(pumpLock),
  'passphrase sheet': _Case(pumpPassphraseSheet),
};

/// Loads the bundled IBM Plex Sans Arabic faces. The default Ahem test font
/// is one em wide per glyph, which overflows rows that fit on a device, so a
/// sweep run on Ahem would report overflows nobody can see.
Future<void> _loadRealFonts() async {
  final loader = FontLoader(kZFontFamily);
  var found = 0;
  for (final f in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final file = File('assets/fonts/IBMPlexSansArabic-$f.ttf');
    if (file.existsSync()) {
      found++;
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await loader.load();
  expect(found, 4, reason: 'assets/fonts must hold the four Plex faces');
}

Future<void> main() async {
  await initDateFormatting();
  setUpAll(_loadRealFonts);
  const variants = <GoldenVariant>[
    GoldenVariant(locale: Locale('ar', 'EG'), dark: false, textScale: 1.3),
    GoldenVariant(locale: Locale('en'), dark: false, textScale: 1.3),
  ];
  for (final v in variants) {
    _cases.forEach((name, c) {
      for (final width in const [360.0, 320.0]) {
        final heights = <double>[640, ?c.tallHeight];
        for (final h in heights) {
          testWidgets('$name ${v.locale.languageCode} x1.3 ${width.toInt()}x'
              '${h.toInt()} has no overflow', (t) async {
            await c.pump(t, v);
            expect(
              t.takeException(),
              isNull,
              reason: 'exception while building at the screen own size',
            );
            await t.binding.setSurfaceSize(Size(width, h));
            addTearDown(() => t.binding.setSurfaceSize(null));
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            expect(
              t.takeException(),
              isNull,
              reason: 'RenderFlex overflow or build error',
            );
          });
        }
      }
    });
  }
}
