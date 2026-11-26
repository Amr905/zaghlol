// T-294: the payday sheet in ar and en, with and without the per-day line,
// reduce motion, plan/close buttons.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol/features/mascot/presentation/payday_sheet.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');

CycleOverview _overview(Money? perDay) => CycleOverview(
  cycle: Cycle(start: CivilDate(2026, 11, 25), end: CivilDate(2026, 12, 25)),
  today: CivilDate(2026, 11, 25),
  daysRemaining: 30,
  byCurrency: {
    if (perDay != null)
      _egp: CurrencyOverview(
        currency: _egp,
        totals: CycleTotals(
          currency: _egp,
          income: Money.zero(_egp),
          spend: Money.zero(_egp),
          pendingSpend: Money.zero(_egp),
          byCategoryMinor: const {},
        ),
        budget: null,
        safeToSpend: perDay,
        underIdealLine: null,
      ),
  },
  incomeTarget: null,
);

Widget host(
  Locale locale, {
  Money? amount,
  Money? perDay,
  bool dark = false,
  double scale = 1.3,
  List<bool>? result,
  Widget? body,
}) {
  final salary = PaydayCelebration('s1', amount ?? Money(_egp, 2970000));
  return ProviderScope(
    overrides: [
      hideAmountsProvider.overrideWithValue(false),
      currentCycleOverviewProvider.overrideWith(
        (ref) async => _overview(perDay),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body:
            body ??
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showPaydaySheet(
                    context,
                    salary,
                    openBudget: () => result?.add(true),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
      ),
    ),
  );
}

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    final ar = locale.languageCode == 'ar';

    testWidgets('content with per-day line (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(host(locale, perDay: Money(_egp, 99000)));
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(ar ? 'وصل المرتب!' : 'Payday is here!'), findsOneWidget);
      expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('payday-per-day')), findsOneWidget);
      expect(find.byKey(const ValueKey('payday-coins')), findsOneWidget);
      expect(
        t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar)).moment.name,
        'payday',
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('per-day line hidden when unknown (${locale.languageCode})', (
      t,
    ) async {
      await t.pumpWidget(host(locale));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('payday-per-day')), findsNothing);
      expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
    });

    testWidgets(
      'USD salary shows USD and no per-day (${locale.languageCode})',
      (t) async {
        await t.pumpWidget(
          host(
            locale,
            amount: Money(Currency.of('USD'), 100000),
            perDay: Money(_egp, 99000),
          ),
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('payday-per-day')), findsNothing);
        final text = t
            .widget<Text>(find.byKey(const ValueKey('payday-amount')))
            .data!;
        expect(text, startsWith('+'));
        expect(text, contains(ar ? '١' : '1'));
        expect(text, isNot(contains('EGP')));
      },
    );

    testWidgets(
      'plan opens the budget, done only closes (${locale.languageCode})',
      (t) async {
        final calls = <bool>[];
        await t.pumpWidget(host(locale, result: calls));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('payday-done')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('payday-amount')), findsNothing);
        expect(calls, isEmpty);
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('payday-plan')));
        await t.pumpAndSettle();
        expect(calls, [true]);
      },
    );

    testWidgets('tapping outside closes (${locale.languageCode})', (t) async {
      await t.pumpWidget(host(locale));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('payday-amount')), findsNothing);
    });

    testWidgets('screen reader announces the amount (${locale.languageCode})', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(locale));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(ar ? 'وصل المرتب، ' : 'Payday is here, ')),
        findsOneWidget,
      );
      h.dispose();
    });

    testWidgets(
      'reduce motion: still bird, no coins (${locale.languageCode})',
      (t) async {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await t.pumpWidget(host(locale));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('payday-coins')), findsNothing);
        expect(find.byKey(const ValueKey('payday-amount')), findsOneWidget);
      },
    );
  }
}
