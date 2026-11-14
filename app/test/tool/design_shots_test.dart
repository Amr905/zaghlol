// Design-review screenshots with real Arabic text (390x844 logical @2x,
// ar + light) to build/design_shots/<screen>.png. Not committed.
//
// Run: `tool/design_shots.sh` (sets DESIGN_SHOTS=1; the tests skip otherwise).
@Tags(['design_shot'])
library;

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
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import '../features/ask/presentation/ask_screen_test.dart' as ask;
import '../features/budget/presentation/budget_test_support.dart' as budget;
import '../features/home/presentation/home_harness.dart' as home;
import '../features/ingestion/presentation/review/review_harness.dart'
    as review;
import '../features/insights/presentation/charts/charts_test_support.dart'
    as charts;
import '../features/money/money_tab_test.dart' as money;
import '../features/onboarding/presentation/android_setup_test.dart' as android;
import '../features/settings/settings_harness.dart' as settings;
import '../features/transactions/presentation/detail_edit_harness.dart' as txn;
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
Future<void> _shot(WidgetTester tester, String name) async {
  // Let asset images (the mascot) finish decoding before capturing.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  RenderRepaintBoundary? best;
  var bestArea = 0.0;
  void visit(Element e) {
    final ro = e.renderObject;
    if (ro is RenderRepaintBoundary && ro.hasSize) {
      final area = ro.size.width * ro.size.height;
      if (area > bestArea) {
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

  testWidgets('home S-10', (tester) async {
    await home.pumpHome(
      tester,
      locale: _ar.locale,
      platform: TargetPlatform.android,
      value: home.model(review: 3),
    );
    await _phone(tester);
    await _shot(tester, 'home');
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
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ZaghlolTheme.light,
          locale: _ar.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: AlignmentDirectional.bottomCenter,
              child: AddSheet(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, 'add_sheet');
  }, skip: _skip != null);
}
