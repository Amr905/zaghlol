// Design-review screenshots with real Arabic text (390x844 logical @2x,
// ar + light) to build/design_shots/<screen>.png. Not committed.
//
// Run: `tool/design_shots.sh` (sets DESIGN_SHOTS=1; the tests skip otherwise).
@Tags(['design_shot'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';
import 'package:zaghlol/core/ui/z_mascot_bubble.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency, Money;
import 'package:zaghlol/features/export_import/presentation/import_done_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/import_source_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_summary_sheet.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../features/export_import/presentation/import_flow_support.dart' as imp;

import 'package:zaghlol/features/accounts/presentation/edit_card/add_card_steps.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/card_details_screen.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/edit_card_providers.dart'
    show InstitutionOption, institutionOptionsProvider;
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';

import '../features/accounts/presentation/card_detail_test.dart' as detail;
import '../features/accounts/presentation/edit_card_test.dart' as edit;
import '../features/capture/presentation/capture_ui_support.dart' as capture;
import '../features/gold/presentation/gold_ui_harness.dart' as gold;
import '../features/capture/presentation/card_capture_sheet_test.dart'
    as capsheet;
import '../features/ask/presentation/ask_screen_test.dart' as ask;
import '../features/budget/presentation/budget_test_support.dart' as budget;
import '../features/home/presentation/home_harness.dart' as home;
import '../features/ingestion/presentation/review/review_harness.dart'
    as review;
import '../features/insights/presentation/charts/charts_test_support.dart'
    as charts;
import '../features/money/money_tab_test.dart' as money;
import '../features/onboarding/presentation/android_setup_test.dart' as android;
import '../features/onboarding/presentation/ios_setup_test.dart' as ios_t;
import '../features/onboarding/presentation/scan_results_test.dart' as scan;
import '../support/ios_setup_host.dart' as ios;

import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/onboarding/presentation/scan_results.dart';

import '../features/settings/settings_harness.dart' as settings;
import '../features/transactions/presentation/detail_edit_harness.dart' as txn;
import '../features/transfers/presentation/transfers_harness.dart' as xfer;
import '../features/voice/voice_harness.dart' as voice;

import 'package:zaghlol/features/transfers/presentation/split_sheet.dart';

import '../features/transactions/presentation/list/list_harness.dart' as list;
import '../support/golden_matrix.dart';
import 'insights_shot_data.dart' as shots;
import '../support/real_fonts.dart';

const _ar = GoldenVariant(locale: Locale('ar', 'EG'), dark: false);
const _outDir = 'build/design_shots';
final _skip = Platform.environment['DESIGN_SHOTS'] == null
    ? 'run tool/design_shots.sh'
    : null;

/// Writes the largest repaint boundary on screen to `<name>.png` at 2x.
Future<void> _shot(
  WidgetTester tester,
  String name, {
  bool topmost = false,
}) async {
  // Asset images decode asynchronously; load them so the mascot shows.
  final images = <Image>[];
  void walk(Element e) {
    if (e.widget is Image) images.add(e.widget as Image);
    e.visitChildren(walk);
  }

  tester.binding.rootElement!.visitChildren(walk);
  await tester.runAsync(() async {
    for (final i in images) {
      await precacheImage(
        i.image,
        tester.element(find.byType(Directionality).first),
      );
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  RenderRepaintBoundary? best;
  var bestArea = 0.0;
  void visit(Element e) {
    final ro = e.renderObject;
    if (ro is RenderRepaintBoundary && ro.hasSize) {
      final area = ro.size.width * ro.size.height;
      if (topmost ? area >= bestArea : area > bestArea) {
        best = ro;
        bestArea = area;
      }
    }
    e.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  final boundary = best!;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// The design size: 390x844 logical.
Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.reset);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    await initDateFormatting();
  });

  Future<void> homeShot(
    WidgetTester tester,
    String name, {
    required TargetPlatform platform,
    bool dark = false,
    Locale locale = const Locale('ar', 'EG'),
    bool review = true,
    bool mascot = true,
    bool scanning = false,
  }) async {
    final en = locale.languageCode == 'en';
    final base = home.model(review: review ? 3 : 0, scanning: scanning);
    final m = HomeModel(
      cycle: base.cycle,
      today: base.today,
      daysRemaining: 7,
      currencies: base.currencies,
      recent: [
        for (final (i, e) in [
          (
            en ? 'Carrefour Maadi' : 'كارفور المعادي',
            'groceries',
            450,
            TxnDirection.expense,
          ),
          (en ? 'Talabat' : 'طلبات', 'dining', 285, TxnDirection.expense),
          (en ? 'Salary' : 'المرتب', 'salary', 32000, TxnDirection.income),
        ].indexed)
          HomeFeedItem(
            record: home.rec(
              't$i',
              merchant: e.$1,
              amount: e.$3,
              dir: e.$4,
              categoryId: e.$2,
            ),
            excludedFromTotals: false,
          ),
      ],
      reviewCount: base.reviewCount,
      scanInProgress: base.scanInProgress,
      cardFilter: const {},
    );
    await home.pumpHome(
      tester,
      locale: locale,
      platform: platform,
      value: m,
      dark: dark,
      withShell: true,
      accounts: [home.account('a1', en ? 'NBE' : 'الأهلي', '4567')],
      actions: mascot
          ? HomeActions(
              openTransactions: () {},
              mascotSlot: ZMascotBubble(
                message: en
                    ? 'Right on track! You saved EGP 2,200 more than last month \u{1F44F}'
                    : 'ماشي بالمسطرة يا صاحبي! وفرت ٢٬٢٠٠ ج.م زيادة عن الشهر اللي فات \u{1F44F}',
              ),
            )
          : HomeActions(openTransactions: () {}),
    );
    await _phone(tester);
    await _shot(tester, name);
  }

  testWidgets('home S-10', (tester) async {
    await homeShot(tester, 'home', platform: TargetPlatform.iOS);
  }, skip: _skip != null);

  testWidgets('home android', (tester) async {
    await homeShot(
      tester,
      'home-android',
      platform: TargetPlatform.android,
      review: false,
      mascot: false,
      scanning: true,
    );
  }, skip: _skip != null);

  testWidgets('home dark', (tester) async {
    await homeShot(
      tester,
      'home-dark',
      platform: TargetPlatform.iOS,
      dark: true,
    );
  }, skip: _skip != null);

  testWidgets('home en', (tester) async {
    await homeShot(
      tester,
      'home-en',
      platform: TargetPlatform.iOS,
      locale: const Locale('en'),
    );
  }, skip: _skip != null);

  testWidgets('money S-40', (tester) async {
    await money.pumpForGolden(tester, _ar);
    await _phone(tester);
    await _shot(tester, 'money');
  }, skip: _skip != null);

  testWidgets('insights charts S-20', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      charts.harness(
        const InsightsScreen(),
        locale: _ar.locale,
        dark: false,
        overrides: [
          ...charts
              .chartOverrides(
                cashFlow: ChartReady(shots.cashFlow()),
                donut: ChartReady(shots.donut()),
              )
              .where((o) => !o.toString().contains('List<CategoryRow>')),
          categoryRowsProvider.overrideWith((ref) async => shots.categories()),
          homeAccountsProvider.overrideWith((ref) async => const []),
        ],
      ),
    );
    await tester.pump();
    await _shot(tester, 'insights_charts');
  }, skip: _skip != null);

  testWidgets('insights chart detail S-21', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      charts.harness(
        const ChartDetailScreen(
          chart: ChartId.categoryDonut,
          code: 'EGP',
          openExplainer: true,
        ),
        locale: _ar.locale,
        dark: false,
        overrides: [
          ...charts
              .chartOverrides(donut: ChartReady(shots.donut()))
              .where((o) => !o.toString().contains('List<CategoryRow>')),
          categoryRowsProvider.overrideWith((ref) async => shots.categories()),

          shots.previousDonutOverride(),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(chartTypingDuration + const Duration(milliseconds: 50));
    await tester.pump();
    await _shot(tester, 'insights_chart_detail');
  }, skip: _skip != null);

  testWidgets('insights budget S-22', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      budget.harness(
        const InsightsScreen(initial: InsightsSegment.budget),
        locale: _ar.locale,
        dark: false,
        overrides: [
          homeAccountsProvider.overrideWith((ref) async => const []),
          budgetScreenDataProvider.overrideWith(
            (ref) async => budget.data([shots.budgetView()]),
          ),
          categoryRowsProvider.overrideWith((ref) async => shots.categories()),
        ],
      ),
    );
    await tester.pump();
    await _shot(tester, 'insights_budget');
  }, skip: _skip != null);

  testWidgets('insights bills S-24', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      budget.harness(
        const InsightsScreen(initial: InsightsSegment.bills),
        locale: _ar.locale,
        dark: false,
        overrides: [
          homeAccountsProvider.overrideWith((ref) async => const []),
          billsDataProvider.overrideWith((ref) async => shots.billsData()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'insights_bills');
  }, skip: _skip != null);

  testWidgets('ask S-50', (tester) async {
    await ask.pump(
      tester,
      ask.FakeEngine((_, _) async => ask.compare()),
      locale: _ar.locale,
    );
    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();
    await _phone(tester);
    await _shot(tester, 'ask');
  }, skip: _skip != null);

  testWidgets('settings S-70', (tester) async {
    final h = settings.SettingsHarness();
    addTearDown(h.db.close);
    await tester.pumpWidget(
      h.app(
        const SettingsMainScreen(),
        locale: _ar.locale,
        dark: false,
        payday: 25,
        appLock: true,
        overrides: [supportCodeProvider.overrideWith((ref) async => 'abc-123')],
      ),
    );
    await settings.settle(tester, height: 844);
    await _shot(tester, 'settings');
  }, skip: _skip != null);

  testWidgets('settings preferences S-72', (tester) async {
    final h = settings.SettingsHarness();
    addTearDown(h.db.close);
    await tester.pumpWidget(
      h.app(
        const PreferencesScreen(),
        locale: _ar.locale,
        dark: false,
        payday: 25,
        appLock: true,
      ),
    );
    await settings.settle(tester, height: 844);
    await _shot(tester, 'settings_preferences');
  }, skip: _skip != null);

  testWidgets('welcome', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ZaghlolTheme.light,
          locale: _ar.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WelcomeScreen(
            onStart: () {},
            onRestore: () {},
            onPrivacy: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'welcome');
  }, skip: _skip != null);

  testWidgets('android setup', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      android.host(android.FakeHost(), android.FakeScan(), 'ar'),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, 'android_setup');
  }, skip: _skip != null);

  testWidgets('transaction detail S-12', (tester) async {
    await txn.pumpDetail(
      tester,
      list.Harness(list.FakeRepo([list.txnRec('a')])),
      detail: AsyncData(
        txn.detailOf(
          list.txnRec('a'),
          raw: 'SYNTHETIC BANK: purchase 450.00 EGP',
        ),
      ),
      locale: _ar.locale,
    );
    await _shot(tester, 'transaction_detail');
  }, skip: _skip != null);

  testWidgets('split sheet S-15', (tester) async {
    await xfer.pumpSheet(
      tester,
      port: xfer.FakePort(split: xfer.sampleSplit()),
      open: (c) => showSplitSheet(c, 'x1'),
      locale: _ar.locale,
      dark: false,
    );
    await _shot(tester, 'split_sheet');
  }, skip: _skip != null);

  testWidgets('transactions list S-11', (tester) async {
    await list.pumpList(
      tester,
      list.Harness(
        list.FakeRepo([list.txnRec('a'), list.txnRec('b'), list.txnRec('c')]),
      ),
      locale: _ar.locale,
    );
    await _shot(tester, 'transactions_list');
  }, skip: _skip != null);

  testWidgets('review queue', (tester) async {
    await review.pumpReview(
      tester,
      review.reviewApp(
        actions: review.FakeActions(),
        queue: review.sampleCards,
        locale: _ar.locale,
        dark: false,
      ),
      size: const Size(390, 844),
    );
    await _shot(tester, 'review_queue');
  }, skip: _skip != null);

  testWidgets('add sheet S-30', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await home.pumpHome(
      tester,
      locale: _ar.locale,
      platform: TargetPlatform.iOS,
      value: home.model(review: 3),
      withShell: true,
    );
    final ctx = tester.element(find.byType(HomeScreen));
    unawaited(
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const AddSheet(voiceLeft: (13, 15)),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'add_sheet', topmost: true);
  }, skip: _skip != null);

  testWidgets('android setup notif (scan progress)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scanFake = android.FakeScan()
      ..cur = const ScanProgress(
        phase: ScanPhase.running,
        imported: 214,
        institutions: 3,
      );
    await tester.pumpWidget(
      android.host(android.FakeHost(granted: true), scanFake, 'ar'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, 'onb_scan_progress');
  }, skip: _skip != null);

  testWidgets('scan results S-06', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const data = ScanResultsData(
      found: 342,
      review: 24,
      cards: [
        ScanCardItem(
          accountId: 'a',
          label: 'الأهلي فيزا ٠٦٧٠',
          kind: AccountKind.debit,
          txnCount: 196,
          institutionCode: 'nbe',
        ),
        ScanCardItem(
          accountId: 'b',
          label: 'CIB ٠٤٣٢١',
          kind: AccountKind.credit,
          txnCount: 88,
          institutionCode: 'cib',
          looksCredit: true,
        ),
        ScanCardItem(
          accountId: 'c',
          label: 'إنستاباي · الأهلي',
          kind: AccountKind.account,
          txnCount: 41,
          institutionCode: 'ip',
        ),
        ScanCardItem(
          accountId: 'd',
          label: 'فودافون كاش',
          kind: AccountKind.wallet,
          txnCount: 17,
          institutionCode: 'vf',
        ),
      ],
    );
    await tester.pumpWidget(scan.host(const AsyncData(data), 'ar'));
    await tester.pumpAndSettle();
    await _shot(tester, 'onb_scan_results');
  }, skip: _skip != null);

  testWidgets('ios setup 1-3', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ios.iosSetupHost(
        'ar',
        reportFn: () => ios.report(
          message: ios.kNow - 3600000,
          wallet: ios.kNow - 10 * ios.kDayMs,
          baseline: ios.kNow - 30 * ios.kDayMs,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'ios_setup_1');
    await ios_t.tapKey(tester, 'ios-setup-to-check');
    await ios_t.tapKey(tester, 'ios-setup-fix-applePay');
    await _shot(tester, 'ios_setup_2');
    await ios_t.tapKey(tester, 'ios-setup-to-first');
    await _shot(tester, 'ios_setup_3');
  }, skip: _skip != null);

  testWidgets('card detail S-41', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      detail.host(
        const CardDetailScreen(accountId: 'a1'),
        overrides: detail.detailOverrides(),
        locale: _ar.locale,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'card_detail');
  }, skip: _skip != null);

  testWidgets('card added S-41 (mockup 31)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      detail.host(
        CardDetailScreen(
          accountId: 'a1',
          justAdded: true,
          onAddTransaction: () {},
          onImportStatement: () {},
        ),
        overrides: [
          ...detail.detailOverrides(
            acc: AccountWithBalances(detail.credit(), const []),
            data: detail.detailData(empty: true),
          ),
          institutionOptionsProvider.overrideWithValue([
            InstitutionOption(
              code: 'cib',
              nameAr: 'CIB',
              nameEn: 'CIB',
              defaultCurrency: Currency.of('EGP'),
              isEgypt: true,
            ),
          ]),
        ],
        locale: _ar.locale,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'card_added');
  }, skip: _skip != null);

  testWidgets('capture controls S-62', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      capture.host(
        capsheet.sheet(),
        controls: capture.FakeControls(
          rules: [capture.rule('1', 'cib', '1234', 'sms')],
        ),
        locale: _ar.locale,
        dark: false,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'capture_controls');
  }, skip: _skip != null);

  testWidgets('add card type', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      edit.host(
        Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => showAddCardTypeSheet(context),
            );
            return const Scaffold();
          },
        ),
        repo: edit.FakeRepo([]),
        locale: _ar.locale,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'add_card_type', topmost: true);
  }, skip: _skip != null);

  testWidgets('add card bank', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      edit.host(
        const BankPicker(),
        repo: edit.FakeRepo([]),
        locale: _ar.locale,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'add_card_bank');
  }, skip: _skip != null);

  testWidgets('add card details', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      edit.host(
        CardDetailsScreen.create(
          kind: AccountKind.credit,
          institution: edit.banks.first,
        ),
        repo: edit.FakeRepo([]),
        locale: _ar.locale,
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'add_card_details');
  }, skip: _skip != null);

  testWidgets('paywall S-68', (tester) async {
    await gold.pumpGold(
      tester,
      gold.goldApp(
        const PaywallScreen(),
        overrides: gold.goldOverrides(gold.FakeGoldActions()),
        lang: 'ar',
        dark: false,
      ),
      height: 844,
    );
    await _shot(tester, 'paywall');
  }, skip: _skip != null);

  testWidgets('voice logger S-31 parsed', (tester) async {
    final r = voice.VoiceRig();
    await r.pump(tester, locale: _ar.locale);
    r.speech.say('دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-done')));
    await tester.pumpAndSettle();
    await _shot(tester, 'voice_logger_parsed', topmost: true);
  }, skip: _skip != null);

  testWidgets('voice logger S-31 listening', (tester) async {
    final r = voice.VoiceRig();
    await r.pump(tester, locale: _ar.locale);
    r.speech.say('دفعت ١٥٠ جنيه خضار و ٤٥ قهوة');
    await tester.pump();
    await _shot(tester, 'voice_logger_listening', topmost: true);
  }, skip: _skip != null);

  Future<ProviderContainer> importShotHost(
    WidgetTester tester,
    Widget screen,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: imp.importOverrides(
        'ar',
        picker: imp.FakePicker(null),
        runner: imp.FakeRunner(),
      ),
    );
    addTearDown(container.dispose);
    container
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: imp.host(screen, lang: 'ar'),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('import source S-67 (32)', (tester) async {
    await importShotHost(tester, const ImportSourceScreen());
    await _shot(tester, 'import_source');
  }, skip: _skip != null);

  testWidgets('import summary S-67 (33)', (tester) async {
    await importShotHost(tester, const ImportSourceScreen());
    unawaited(
      showImportSummarySheet(
        tester.element(find.byType(ImportSourceScreen)),
        preview: imp.samplePreview(card: 'CIB'),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'import_summary', topmost: true);
  }, skip: _skip != null);

  testWidgets('import done S-67 (34)', (tester) async {
    await importShotHost(
      tester,
      ImportDoneScreen(
        cardName: 'CIB',
        onReview: () {},
        outcome: ImportOutcome(
          imported: 143,
          earliest: DateTime.utc(2026, 8, 5),
          latest: DateTime.utc(2026, 10, 25),
          autoCategorised: 131,
          needReview: 11,
          topCategories: [
            ImportTopCategory(
              categoryId: 'sys:dining',
              name: 'أكل بره',
              total: Money(Currency.of('EGP'), 342000),
            ),
            ImportTopCategory(
              categoryId: 'sys:groceries',
              name: 'خزين البيت',
              total: Money(Currency.of('EGP'), 288000),
            ),
            ImportTopCategory(
              categoryId: 'sys:transport',
              name: 'سفر',
              total: Money(Currency.of('EGP'), 215000),
            ),
          ],
        ),
      ),
    );
    await _shot(tester, 'import_done');
  }, skip: _skip != null);
}
