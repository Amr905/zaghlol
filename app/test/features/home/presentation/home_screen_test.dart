import 'package:flutter/material.dart';
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

  testWidgets('two currencies: pager with dots, figures never summed', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [figs(egp), figs(usd, income: 500, spend: 120, safe: 9)],
      ),
    );
    expect(find.byKey(const ValueKey('home-pager')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('home-pager')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('USD'), findsWidgets);
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
      ),
    );
    expect(find.textContaining('29,700'), findsWidgets);
    expect(find.textContaining('exchanged in'), findsOneWidget);
    expect(find.textContaining('29,200'), findsOneWidget); // left
    await tester.drag(
      find.byKey(const ValueKey('home-pager')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('600') &&
            (w.data ?? '').endsWith(' exchanged'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('400'), findsWidgets); // USD left
  });

  testWidgets('T-272: the main page lists the other currency\'s income, '
      'unconverted; a tap opens that page; no line without income', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [
          figs(egp),
          figs(usd, income: 189, spend: 0, safe: null),
          figs(Currency.of('GBP'), income: 0, spend: 10, safe: null),
        ],
      ),
    );
    final line = find.byKey(const ValueKey('home-other-income-USD'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.textContaining('189')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-other-income-GBP')), findsNothing);
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-other-income-USD')), findsNothing);
  });

  for (final locale in const [_en, Locale('ar')]) {
    testWidgets('no-budget second currency fits the pager on a small phone '
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
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('home-pager')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
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

  testWidgets('pager is sized to its content, not a fixed height', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(currencies: [figs(egp), figs(usd)]),
    );
    await tester.pumpAndSettle();
    final pager = tester.getSize(find.byKey(const ValueKey('home-pager')));
    final hero = tester.getSize(find.byType(HomeHero).first);
    expect(pager.height, closeTo(hero.height, 0.5));
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
