// T-174: guideline + 1.3x sweep over Budget, Bills, Welcome, Backup, Restore,
// Transactions list and Android setup. ar/en x light/dark x scale 1.0/1.3
// (Android setup: light only, its test host has no dark theme).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/backup/presentation/backup_screen.dart';
import 'package:zaghlol/features/backup/presentation/restore_flow.dart';
import 'package:zaghlol/features/backup/presentation/restore_screen.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_screen.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';
import 'package:zaghlol/features/recurring/presentation/bill_edit_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bills_screen.dart';

import '../features/backup/presentation/backup_fakes.dart' as bk;
import '../features/budget/presentation/budget_test_support.dart';
import '../features/onboarding/presentation/android_setup_test.dart' as android;
import '../features/onboarding/presentation/android_setup_test.dart'
    show FakeHost, FakeScan;
import '../features/recurring/presentation/bills_screen_test.dart' show full;
import '../features/transactions/presentation/list/list_harness.dart';
import '../support/a11y_guidelines.dart';
import '../support/golden_matrix.dart';

void main() {
  setUpAll(initDateFormatting);
  final now = DateTime.utc(2026, 11, 14);

  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;
    final tag = v.name;

    testWidgets('budget a11y $tag', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          const BudgetScreen(),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: [
            budgetScreenDataProvider.overrideWith(
              (ref) async => data([egpView(), usdView()]),
            ),
          ],
        ),
      );
      await t.pump();
      await expectA11yGuidelines(t);
    });

    for (final screen in ['bills', 'bill edit']) {
      testWidgets('$screen a11y $tag', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          harness(
            screen == 'bills' ? const BillsScreen() : const BillEditScreen(),
            locale: v.locale,
            dark: v.dark,
            scale: v.textScale,
            overrides: [billsDataProvider.overrideWith((ref) async => full())],
          ),
        );
        await t.pumpAndSettle();
        await expectA11yGuidelines(t);
      });
    }

    testWidgets('welcome a11y $tag', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZaghlolTheme.light,
            darkTheme: ZaghlolTheme.dark,
            themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
            locale: v.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(v.textScale)),
              child: child!,
            ),
            home: WelcomeScreen(
              onStart: () {},
              onRestore: () {},
              onPrivacy: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('backup a11y $tag', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final gw = bk.FakeGateway()
        ..entries = [
          bk.entry(now),
          bk.entry(now.subtract(const Duration(days: 7))),
        ];
      await t.pumpWidget(
        ProviderScope(
          overrides: bk.baseOverrides(
            lang: lang,
            gateway: gw,
            actions: bk.FakeActions(),
            last: now.subtract(const Duration(days: 2)),
          ),
          child: bk.host(
            BackupScreen(onOpenRestore: () {}, now: () => now),
            lang: lang,
            scale: v.textScale,
            dark: v.dark,
          ),
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('restore a11y $tag', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final gw = bk.FakeGateway()
        ..entries = [
          bk.entry(now),
          bk.entry(now.subtract(const Duration(days: 7))),
        ];
      await t.pumpWidget(
        ProviderScope(
          overrides: bk.baseOverrides(
            lang: lang,
            gateway: gw,
            effects: bk.FakeEffects(),
          ),
          child: bk.host(
            RestoreScreen(
              onRestored: ({required regrantDue}) {},
              onStartFresh: () {},
            ),
            lang: lang,
            scale: v.textScale,
            dark: v.dark,
          ),
        ),
      );
      await t.pumpAndSettle();
      final c = ProviderScope.containerOf(
        t.element(find.byType(RestoreScreen)),
      );
      await c.read(restoreFlowProvider.notifier).search();
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('transactions list a11y $tag', (t) async {
      await pumpList(
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
      );
      await expectA11yGuidelines(t);
    });

    if (!v.dark) {
      testWidgets('android setup a11y $tag', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          android.host(FakeHost(), FakeScan(), lang, scale: v.textScale),
        );
        await t.pump(const Duration(milliseconds: 200));
        await expectA11yGuidelines(t);
      });
    }
  }
}
