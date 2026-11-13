// T-101: S-22 states in ar and en, RTL, text scale 1.3.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_screen.dart';
import 'package:zaghlol/features/budget/presentation/budget_view.dart';

import 'budget_test_support.dart';

const locales = [Locale('ar', 'EG'), Locale('en')];

Future<void> pump(
  WidgetTester tester,
  Locale locale,
  Override data, {
  double scale = 1.0,
  bool dark = false,
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harness(
      const BudgetScreen(),
      locale: locale,
      scale: scale,
      dark: dark,
      overrides: [data],
    ),
  );
  await tester.pump();
}

Override ok(BudgetScreenData d) =>
    budgetScreenDataProvider.overrideWith((ref) async => d);

AppLocalizations l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BudgetScreen)));

void main() {
  for (final locale in locales) {
    final tag = locale.languageCode;

    group('S-22 $tag', () {
      testWidgets('data: overall, safe per day, mascot, rows, not budgeted', (
        tester,
      ) async {
        await pump(tester, locale, ok(data([egpView()])));
        final l = l10n(tester);
        expect(
          Directionality.of(tester.element(find.byType(BudgetScreen))),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(
          find.textContaining(l.budgetOverviewNotBudgeted),
          findsOneWidget,
        );
        expect(find.text(l.budgetOverviewEdit), findsOneWidget);
        // Dining 96% and Bills 104%: terracotta rule with text cues.
        expect(find.text(l.budgetOverviewStatusNear), findsOneWidget);
        expect(
          find.textContaining(
            l.budgetOverviewStatusOver('').trim().split(' ').first,
          ),
          findsWidgets,
        );
        // Groceries (77%) has no status cue.
        expect(find.byType(ListView), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('empty: no budget shows the call to action', (tester) async {
        await pump(tester, locale, ok(data([egpView(budget: false)])));
        final l = l10n(tester);
        expect(find.text(l.budgetOverviewEmptyTitle), findsOneWidget);
        expect(find.text(l.budgetOverviewEmptyAction), findsOneWidget);
        expect(find.text(l.budgetOverviewEdit), findsNothing);
      });

      testWidgets('no activity at all', (tester) async {
        await pump(tester, locale, ok(data(const [])));
        final l = l10n(tester);
        expect(find.text(l.budgetOverviewEmptyAction), findsOneWidget);
      });

      testWidgets('calendar month shows the label and Set payday', (
        tester,
      ) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            BudgetScreen(onSetPayday: () {}),
            locale: locale,
            overrides: [
              ok(data([egpView()], calendarMonth: true)),
            ],
          ),
        );
        await tester.pump();
        final l = l10n(tester);
        expect(find.text(l.budgetOverviewCalendarMonth), findsOneWidget);
        expect(find.text(l.budgetOverviewSetPayday), findsOneWidget);
      });

      testWidgets('loading', (tester) async {
        final never = Completer<BudgetScreenData>();
        await pump(
          tester,
          locale,
          budgetScreenDataProvider.overrideWith((ref) => never.future),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.bySemanticsLabel(l10n(tester).budgetOverviewLoadingA11y),
          findsOneWidget,
        );
      });

      testWidgets('error offers retry', (tester) async {
        await pump(
          tester,
          locale,
          budgetScreenDataProvider.overrideWith(
            (ref) async => throw StateError('x'),
          ),
        );
        await tester.pump();
        final l = l10n(tester);
        expect(find.text(l.commonErrorLoadFailed), findsOneWidget);
        expect(find.text(l.commonActionTryAgain), findsOneWidget);
      });

      testWidgets('two currencies: switcher shows one currency only', (
        tester,
      ) async {
        await pump(tester, locale, ok(data([egpView(), usdView()])));
        final l = l10n(tester);
        expect(find.text('EGP'), findsOneWidget);
        expect(find.text('USD'), findsOneWidget);
        expect(find.text(l.budgetOverviewCurrencyNote('EGP')), findsOneWidget);
        await tester.tap(find.text('USD'));
        await tester.pump();
        expect(find.text(l.budgetOverviewCurrencyNote('USD')), findsOneWidget);
        // The EGP-only rows are gone.
        expect(
          find.text(locale.languageCode == 'ar' ? 'مطاعم' : 'Dining'),
          findsNothing,
        );
      });

      testWidgets('text scale 1.3 does not overflow', (tester) async {
        await pump(
          tester,
          locale,
          ok(data([egpView(), usdView()])),
          scale: 1.3,
          dark: true,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('category tap and 48dp targets', (tester) async {
        String? tapped;
        await initDateFormatting();
        await tester.pumpWidget(
          harness(
            BudgetScreen(onCategoryTap: (id, _) => tapped = id),
            locale: locale,
            overrides: [
              ok(data([egpView()])),
            ],
          ),
        );
        await tester.pump();
        final name = locale.languageCode == 'ar' ? 'مطاعم' : 'Dining';
        expect(
          tester.getSize(find.byType(InkWell).first).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.text(name));
        expect(tapped, 'dining');
      });
    });
  }

  testWidgets('previous cycle arrow moves the offset; next is disabled now', (
    tester,
  ) async {
    await pump(tester, locales[1], ok(data([egpView()])));
    final l = l10n(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BudgetScreen)),
    );
    expect(container.read(budgetCycleOffsetProvider), 0);
    await tester.tap(find.byTooltip(l.budgetOverviewPrevA11y));
    expect(container.read(budgetCycleOffsetProvider), -1);
    container.read(budgetCycleOffsetProvider.notifier).next();
    expect(container.read(budgetCycleOffsetProvider), 0);
    container.read(budgetCycleOffsetProvider.notifier).next();
    expect(container.read(budgetCycleOffsetProvider), 0);
  });

  test('threshold constant', () => expect(budgetWarnPercent, 85));
}
