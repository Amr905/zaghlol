import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/home/presentation/currency_cards.dart';
import 'package:zaghlol/features/home/presentation/home_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol/core/brand/institution_brand.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/core/l10n/card_number.dart';
import 'package:zaghlol/core/ui/z_banner.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart'
    show HomeHero, HomeKpis;

import 'home_harness.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

/// All text inside one currency card, bidi isolates removed.
String cardText(WidgetTester tester, String code) {
  final texts = find.descendant(
    of: find.byKey(ValueKey('home-currency-card-$code')),
    matching: find.byType(Text),
  );
  return [
    for (final t in texts.evaluate())
      ((t.widget as Text).data ?? '').replaceAll(RegExp('[\u2066-\u2069]'), ''),
  ].join('|');
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final locale in [_ar, _en]) {
      for (final scale in [1.0, 1.3]) {
        final tag = '${platform.name} ${locale.languageCode} x$scale';

        testWidgets('data state, no overflow ($tag)', (tester) async {
          await pumpHome(
            tester,
            locale: locale,
            platform: platform,
            value: model(review: 3),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('home-review')), findsOneWidget);
          expect(find.byKey(const ValueKey('home-row-t1')), findsOneWidget);
          expect(find.byKey(const ValueKey('home-greeting')), findsOneWidget);
          final dir = Directionality.of(
            tester.element(find.byType(HomeScreen)),
          );
          expect(
            dir,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
        });
      }
    }
  }

  testWidgets('hero shows safe to spend, en digits and EGP', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.textContaining('314'), findsOneWidget);
    expect(find.textContaining('EGP'), findsWidgets);
  });

  testWidgets('ar renders Arabic-Indic digits and the ج.م symbol', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _ar,
      platform: TargetPlatform.android,
      value: model(),
    );
    expect(find.textContaining('٣١٤'), findsOneWidget);
    expect(find.textContaining('ج.م'), findsWidgets);
  });

  testWidgets('spending amounts are ink, not red', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    final t = tester.widget<Text>(find.textContaining('-').first);
    final c = t.style!.color!;
    expect(c.r > 0.5 && c.g < 0.3 && c.b < 0.3, isFalse);
  });

  testWidgets('no budget: hero offers Set a budget, no safe-to-spend', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(currencies: [figs(egp, safe: null)]),
    );
    expect(find.text('Set a budget'), findsOneWidget);
    expect(find.text('Safe to spend today'), findsNothing);
    // D-82: the cycle starting 25 Oct is the November cycle.
    expect(find.text('Spent in November'), findsOneWidget);
  });

  testWidgets('two currencies: one EGP hero page, USD is a small card, '
      'never summed', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [figs(egp), figs(usd, income: 500, spend: 120, safe: 9)],
        cards: [cardOf(usd)],
      ),
    );
    expect(find.byKey(const ValueKey('home-pager')), findsNothing);
    expect(find.byType(HomeHero), findsOneWidget);
    expect(find.text('Other currencies'), findsOneWidget);
    expect(cardText(tester, 'USD'), 'USD 380.00 left|In 500 · Out 120');
  });

  testWidgets('T-272: income KPI shows money in with the exchanged-in line; '
      'spent stays spending with an exchanged line', (tester) async {
    HomeCurrencyFigures withX(
      Currency c, {
      required int income,
      required int spend,
      int xin = 0,
      int xout = 0,
    }) {
      final t = CycleTotals(
        currency: c,
        income: Money(c, income),
        spend: Money(c, spend),
        pendingSpend: Money(c, 0),
        byCategoryMinor: const {},
        exchangedIn: Money(c, xin),
        exchangedOut: Money(c, xout),
      );
      return HomeCurrencyFigures(
        overview: CurrencyOverview(
          currency: c,
          totals: t,
          budget: null,
          safeToSpend: null,
          underIdealLine: null,
        ),
        net: t.left,
      );
    }

    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [
          withX(egp, income: 0, spend: 50000, xin: 2970000),
          withX(usd, income: 100000, spend: 0, xout: 60000),
        ],
        cards: [
          HomeCurrencyCard(
            figures: withX(usd, income: 100000, spend: 0, xout: 60000),
            lastActivity: CivilDate(2026, 11, 9),
          ),
        ],
      ),
    );
    // PO story (plan §2): EGP hero shows 29,700 in, USD card shows 400 left.
    expect(find.textContaining('29,700'), findsWidgets);
    expect(find.textContaining('exchanged in'), findsOneWidget);
    expect(find.textContaining('29,200'), findsOneWidget); // EGP left
    expect(cardText(tester, 'USD'), 'USD 400.00 left|In 1,000 · Out 600');
  });

  testWidgets('T-278: cards show at most 3, then a +N chip opening the '
      'rest; most recent activity first; a tap opens that currency', (
    tester,
  ) async {
    final codes = ['USD', 'GBP', 'EUR', 'SAR', 'AED'];
    // Activity days: GBP newest, then AED, USD, EUR, SAR oldest.
    final days = {'GBP': 20, 'AED': 18, 'USD': 15, 'EUR': 12, 'SAR': 5};
    final cards = orderCurrencyCards([
      for (final c in codes)
        cardOf(Currency.of(c), last: CivilDate(2026, 11, days[c]!)),
    ]);
    expect(
      [for (final c in cards) c.currency.code],
      ['GBP', 'AED', 'USD', 'EUR', 'SAR'],
    );
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [figs(egp), for (final c in cards) figs(c.currency)],
        cards: cards,
      ),
    );
    for (final c in ['GBP', 'AED', 'USD']) {
      expect(
        find.byKey(ValueKey('home-currency-card-$c')),
        findsOneWidget,
        reason: c,
      );
    }
    expect(find.byKey(const ValueKey('home-currency-card-EUR')), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('home-currency-more')),
    );
    await tester.tap(find.byKey(const ValueKey('home-currency-more')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home-currency-card-EUR')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-currency-card-SAR')),
      findsOneWidget,
    );
  });

  testWidgets('T-278: a card tap calls the open hook with its currency', (
    tester,
  ) async {
    Currency? opened;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: _en,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ZaghlolTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => HomeCurrencyCards(
                  cards: [cardOf(usd)],
                  format: HomeFormat.of(context, ref),
                  onOpen: (c) => opened = c,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('home-currency-card-USD')));
    expect(opened, usd);
  });

  testWidgets('T-278: the ≈ slot builder renders under the cards, nothing '
      'when null', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(currencies: [figs(egp)], cards: [cardOf(usd)]),
      extraOverrides: [
        homeApproxSlotBuilder.overrideWithValue(
          (_) => const Text('approx-slot', key: ValueKey('approx-slot')),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('approx-slot')), findsOneWidget);
  });

  testWidgets('T-278: Arabic card says فاضل USD with Arabic-Indic digits', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: const Locale('ar'),
      platform: TargetPlatform.android,
      value: model(
        currencies: [figs(egp)],
        cards: [cardOf(usd, income: 400, spend: 0)],
      ),
    );
    expect(find.text('فلوسك بعملات تانية'), findsOneWidget);
    expect(cardText(tester, 'USD'), contains('فاضل'));
    expect(cardText(tester, 'USD'), contains('٤٠٠٫٠٠'));
  });

  testWidgets('T-278: EGP only: no currency UI at all', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    expect(find.text('Other currencies'), findsNothing);
    expect(find.byKey(const ValueKey('home-currency-cards')), findsNothing);
  });

  testWidgets('T-278: only a foreign currency has data: EGP hero stays '
      '(zeros), USD card shows', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(currencies: [figs(usd)], cards: [cardOf(usd)]),
    );
    expect(find.byType(HomeHero), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-currency-card-USD')),
      findsOneWidget,
    );
  });

  for (final locale in const [_en, Locale('ar')]) {
    testWidgets('currency cards fit a small phone '
        '(${locale.languageCode})', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHome(
        tester,
        locale: locale,
        platform: TargetPlatform.android,
        value: model(
          currencies: [
            figs(egp),
            figs(usd, income: 500, spend: 120, safe: null),
          ],
          cards: [
            for (final c in ['USD', 'GBP', 'EUR', 'SAR'])
              cardOf(Currency.of(c), income: 123456789),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in const [_en, Locale('ar')]) {
    testWidgets(
      'KPI figures keep a gap on a small phone (${locale.languageCode})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpHome(
          tester,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(
            currencies: [figs(egp, income: 3209900, spend: 2833390, safe: 1)],
          ),
        );
        final boxes = find.descendant(
          of: find.byType(HomeKpis),
          matching: find.byType(FittedBox),
        );
        expect(boxes, findsNWidgets(3));
        final rects = [for (var i = 0; i < 3; i++) tester.getRect(boxes.at(i))]
          ..sort((a, b) => a.left.compareTo(b.left));
        expect(rects[1].left - rects[0].right, greaterThanOrEqualTo(8));
        expect(rects[2].left - rects[1].right, greaterThanOrEqualTo(8));
      },
    );
  }

  testWidgets('one currency: no pager', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    expect(find.byKey(const ValueKey('home-pager')), findsNothing);
  });

  testWidgets('review pill hidden at zero', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.byKey(const ValueKey('home-review')), findsNothing);
  });

  testWidgets('scan banner while scanning', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(scanning: true),
    );
    expect(find.byKey(const ValueKey('home-scan-banner')), findsOneWidget);
  });

  testWidgets('internal transfer is labelled, not red, not signed as spend', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.textContaining('To yourself'), findsWidgets);
  });

  testWidgets('empty: add action when SMS is not waiting', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(currencies: [], recent: []),
    );
    expect(find.byKey(const ValueKey('home-empty')), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Add first expense'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hero-empty')), findsOneWidget);
  });

  testWidgets('empty with SMS on: waiting copy, no add button', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(currencies: [], recent: []),
      smsWaiting: true,
    );
    expect(find.textContaining('as soon as a bank message'), findsOneWidget);
    expect(find.text('Add first expense'), findsNothing);
  });

  testWidgets('filter empty names the card (EC-61) and clears', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(recent: [], filter: {'a1'}),
      filter: {'a1'},
      accounts: [account('a1', 'CIB', '1234')],
    );
    await tester.pump();
    expect(
      find.textContaining('${formatAccountWithCard('CIB', '1234')} this month'),
      findsOneWidget,
    );
    expect(find.text('Clear filter'), findsWidgets);
  });

  testWidgets('loading shows skeleton', (tester) async {
    final c = pending();
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      future: c.future,
      settle: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-skeleton')), findsOneWidget);
  });

  testWidgets('error shows inline banner with retry', (tester) async {
    final c = pending();
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      future: c.future,
      settle: false,
    );
    c.completeError(StateError('x'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('home-error')), findsOneWidget);
    expect(find.byType(ZBanner), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('feed row account line falls back to the bank acronym', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = Account(
      id: 'a1',
      kind: AccountKind.values.first,
      label: 'البنك الأهلي المصري للتجارة والاستثمار',
      institutionCode: 'nbe',
      last4: '5075',
      defaultCurrency: egp,
      isHidden: false,
      isDefaultCash: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await pumpHome(
      tester,
      locale: _ar,
      platform: TargetPlatform.android,
      textScale: 1.3,
      value: model(),
      accounts: [long],
      extraOverrides: [
        institutionBrandsProvider.overrideWith(
          (ref) async => {'nbe': const InstitutionBrand(acronym: 'NBE')},
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('NBE'), findsWidgets);
    expect(find.textContaining('للتجارة'), findsNothing);
  });

  group('cycle naming (D-82, T-247)', () {
    final noBudget = [figs(egp, safe: null)];

    testWidgets('a cycle starting on day 24 is named after the next month', (
      tester,
    ) async {
      await pumpHome(
        tester,
        locale: _en,
        platform: TargetPlatform.iOS,
        value: model(
          currencies: noBudget,
          cycle: Cycle(
            start: CivilDate(2026, 11, 24),
            end: CivilDate(2026, 12, 23),
          ),
        ),
      );
      expect(find.text('Spent in December'), findsOneWidget);
    });

    testWidgets('Dec 24 is January, in Arabic', (tester) async {
      await pumpHome(
        tester,
        locale: _ar,
        platform: TargetPlatform.iOS,
        value: model(
          currencies: noBudget,
          cycle: Cycle(
            start: CivilDate(2026, 12, 24),
            end: CivilDate(2027, 1, 23),
          ),
        ),
      );
      expect(find.text('صرفت في يناير'), findsOneWidget);
    });

    testWidgets('a cycle starting on day 20 is its own month', (tester) async {
      await pumpHome(
        tester,
        locale: _en,
        platform: TargetPlatform.iOS,
        value: model(
          currencies: noBudget,
          cycle: Cycle(
            start: CivilDate(2026, 11, 20),
            end: CivilDate(2026, 12, 19),
          ),
        ),
      );
      expect(find.text('Spent in November'), findsOneWidget);
    });
  });
}
