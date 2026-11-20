// T-174: one pump function per screen, shared by the guideline tests and the
// goldens so both look at exactly the same widget tree.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/backup/presentation/passphrase_sheet.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/edit_budgets_screen.dart';
import 'package:zaghlol/features/capture/presentation/card_capture_sheet.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';
import 'package:zaghlol/features/security/presentation/lock_screen.dart';

import '../features/account/presentation/account_screen_test.dart' as account;
import '../features/accounts/presentation/card_detail_test.dart' as detail;
import '../features/backup/presentation/backup_fakes.dart' as backup;
import '../features/budget/presentation/budget_test_support.dart';
import '../features/capture/presentation/capture_ui_support.dart' as capture;
import '../features/capture/presentation/template_builder_screen_test.dart'
    as tb;
import '../features/home/presentation/home_harness.dart' as home;
import '../features/settings/settings_harness.dart';
import '../support/golden_matrix.dart';

Locale _loc(GoldenVariant v) => v.locale;

Future<void> pumpAccountS69(WidgetTester t, GoldenVariant v) =>
    account.pumpAccount(
      t,
      account.FakeAccountActions(),
      v.locale.languageCode,
      dark: v.dark,
      scale: v.textScale,
    );

Future<void> pumpEditBudgets(WidgetTester t, GoldenVariant v) async {
  await initDateFormatting();
  await t.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    harness(
      EditBudgetsScreen(initialCurrency: egp),
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
      overrides: [
        categoryRowsProvider.overrideWith((ref) async => const []),
        cycleBudgetRowsProvider.overrideWith((ref) async => const []),
      ],
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pumpInsightsShell(WidgetTester t, GoldenVariant v) async {
  await initDateFormatting();
  await t.binding.setSurfaceSize(const Size(390, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    harness(
      InsightsScreen(
        chartsBuilder: (_) => const Text('charts-body'),
        billsBuilder: (_) => const Text('bills-body'),
      ),
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
      overrides: [
        budgetScreenDataProvider.overrideWith((ref) async => data([egpView()])),
      ],
    ),
  );
  await t.pump();
}

Future<void> pumpLock(WidgetTester t, GoldenVariant v) async {
  await t.binding.setSurfaceSize(const Size(360, 640));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    harness(
      LockScreen(outcome: AuthOutcome.lockedOut, busy: false, onUnlock: () {}),
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
    ),
  );
  await t.pump();
}

Future<void> pumpTemplateBuilder(WidgetTester t, GoldenVariant v) async {
  tb.bigScreen(t);
  final h = SettingsHarness();
  addTearDown(h.db.close);
  await t.pumpWidget(
    tb.host(
      h,
      tb.FakeStore(),
      lang: v.locale.languageCode,
      scale: v.textScale,
      dark: v.dark,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pumpPassphraseSheet(WidgetTester t, GoldenVariant v) async {
  final lang = v.locale.languageCode;
  await t.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: backup.baseOverrides(lang: lang),
      child: backup.host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showPassphraseSheet(context, mode: PassphraseMode.setup),
              child: const Text('open'),
            ),
          ),
        ),
        lang: lang,
        scale: v.textScale,
        dark: v.dark,
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Future<void> pumpHomeCardFilterSheet(WidgetTester t, GoldenVariant v) async {
  await t.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    detail.host(
      const Scaffold(body: HomeCardFilterSheet()),
      overrides: [
        homeAccountsProvider.overrideWith(
          (ref) async => [
            home.account('a1', 'CIB Credit', '1234'),
            home.account('a2', 'NBE Platinum', '5678'),
          ],
        ),
      ],
      locale: v.locale,
      dark: v.dark,
      scale: v.textScale,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pumpCardCaptureSheet(WidgetTester t, GoldenVariant v) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    capture.host(
      const Scaffold(
        body: SingleChildScrollView(
          child: CardCaptureControls(
            institutionCode: 'cib',
            last4: '1234',
            cardName: 'CIB 1234',
          ),
        ),
      ),
      controls: capture.FakeControls(),
      locale: _loc(v),
      scale: v.textScale,
      dark: v.dark,
    ),
  );
  await t.pumpAndSettle();
}
