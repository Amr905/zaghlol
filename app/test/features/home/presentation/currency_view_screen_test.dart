// T-279: per-currency view, one test per state and acceptance criterion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/home/application/currency_view_providers.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/home/presentation/currency_view_screen.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'currency_view_harness.dart';

const _en = Locale('en');
const _ar = Locale('ar', 'EG');

List<String> allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void main() {
  for (final locale in [_ar, _en]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'PO story: USD only, no EGP figure (${locale.languageCode} x$scale)',
        (tester) async {
          await pumpView(
            tester,
            viewApp(
              iso: 'USD',
              env: ViewEnv(),
              locale: locale,
              textScale: scale,
            ),
            height: 1800,
          );
          expect(tester.takeException(), isNull);
          final text = allText(tester).join(' | ');
          // money in 1,000, exchanged out 600, left 400 (digits per locale).
          final en = locale.languageCode == 'en';
          expect(text, contains(en ? '1,000' : '١٬٠٠٠'));
          expect(text, contains(en ? '600' : '٦٠٠'));
          expect(text, contains(en ? '400' : '٤٠٠'));
          // Feed: the salary and the exchange.
          expect(
            find.byKey(const ValueKey('currency-row-salary')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('currency-row-exch')),
            findsOneWidget,
          );
          // Nothing of the other currency.
          expect(
            find.byKey(const ValueKey('currency-row-egp-row')),
            findsNothing,
          );
          expect(text, isNot(contains('EGP')));
          expect(text, isNot(contains('ج.م')));
          expect(text, isNot(contains(en ? '29,700' : '٢٩٬٧٠٠')));
          expect(
            find.text(en ? 'This month in USD' : 'الشهر ده بالـUSD'),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('hero is the Home hero in this currency', (tester) async {
    await pumpView(tester, viewApp(iso: 'usd', env: ViewEnv(), locale: _en));
    expect(find.byType(HomeHero), findsOneWidget);
  });

  testWidgets('unknown code: friendly empty state, no crash', (tester) async {
    await pumpView(tester, viewApp(iso: 'ZZZ', env: ViewEnv(), locale: _en));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('currency-view-empty')), findsOneWidget);
    expect(find.byType(HomeHero), findsNothing);
  });

  testWidgets('a currency with no activity shows the empty state', (
    tester,
  ) async {
    await pumpView(tester, viewApp(iso: 'GBP', env: ViewEnv(), locale: _ar));
    expect(find.byKey(const ValueKey('currency-view-empty')), findsOneWidget);
  });

  testWidgets('loading state', (tester) async {
    final c = Completer<HomeModel>();
    await pumpView(
      tester,
      viewApp(iso: 'USD', env: ViewEnv(), future: c.future),
      settle: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('currency-view-loading')), findsOneWidget);
  });

  testWidgets('error state with retry', (tester) async {
    await pumpView(
      tester,
      viewApp(iso: 'USD', env: ViewEnv(), locale: _en, fail: true),
    );
    expect(find.byKey(const ValueKey('currency-view-error')), findsOneWidget);
  });

  testWidgets('see all passes this currency', (tester) async {
    Currency? seen;
    await pumpView(
      tester,
      viewApp(
        iso: 'USD',
        env: ViewEnv(),
        locale: _en,
        onSeeAll: (c) => seen = c,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('currency-view-see-all')));
    expect(seen, usd);
  });

  group('budget offer', () {
    testWidgets('shown for USD with activity and no budget', (tester) async {
      await pumpView(tester, viewApp(iso: 'USD', env: ViewEnv(), locale: _en));
      expect(find.text('Want a USD budget?'), findsOneWidget);
    });

    testWidgets('Arabic copy', (tester) async {
      await pumpView(tester, viewApp(iso: 'USD', env: ViewEnv(), locale: _ar));
      expect(find.text('تعمل ميزانية بالـUSD؟'), findsOneWidget);
    });

    testWidgets('dismiss is remembered and the offer goes away', (
      tester,
    ) async {
      final env = ViewEnv();
      await pumpView(tester, viewApp(iso: 'USD', env: env, locale: _en));
      await tester.tap(find.bySemanticsLabel('Dismiss').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(env.settings.value, {budgetOfferSlug(usd, cycle.start)});
      expect(find.byKey(const ValueKey('currency-view-offer')), findsNothing);
    });

    testWidgets('already handled this month: not shown', (tester) async {
      final env = ViewEnv(handled: {budgetOfferSlug(usd, cycle.start)});
      await pumpView(tester, viewApp(iso: 'USD', env: env, locale: _en));
      expect(find.byKey(const ValueKey('currency-view-offer')), findsNothing);
    });

    testWidgets('Yes opens the editor with USD and remembers', (tester) async {
      Currency? opened;
      final env = ViewEnv();
      await pumpView(
        tester,
        viewApp(iso: 'USD', env: env, locale: _en, onEditor: (c) => opened = c),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('currency-view-offer')),
          matching: find.text('Yes'),
        ),
      );
      await tester.pump();
      expect(opened, usd);
      expect(env.settings.value, isNotEmpty);
    });

    testWidgets('never shown when a USD budget exists', (tester) async {
      await pumpView(
        tester,
        viewApp(
          iso: 'USD',
          env: ViewEnv(),
          locale: _en,
          model: storyModel(usdBudget: 500),
        ),
      );
      expect(find.byKey(const ValueKey('currency-view-offer')), findsNothing);
    });

    testWidgets('never offered for the primary currency', (tester) async {
      await pumpView(tester, viewApp(iso: 'EGP', env: ViewEnv(), locale: _en));
      expect(find.byKey(const ValueKey('currency-view-offer')), findsNothing);
    });
  });
}
