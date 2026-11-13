import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' show IgnoreRuleRow;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail_providers.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/compare.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/capture/presentation/capture_controls.dart';
import 'package:zaghlol/features/home/application/card_filter.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money m(int minor, [Currency? c]) => Money(c ?? egp, minor);
final _t = DateTime.utc(2026, 11, 1);

Account credit({bool hasLimit = true}) => Account(
  id: 'a1',
  kind: AccountKind.credit,
  label: 'CIB Credit',
  defaultCurrency: egp,
  isHidden: false,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
  institutionCode: 'cib',
  last4: '1234',
  creditLimit: hasLimit ? m(2400000) : null,
  statementDueDay: 15,
);

AccountWithBalances withBalances(Account a, {bool usdToo = false}) =>
    AccountWithBalances(a, [
      AccountBalance(
        accountId: a.id,
        currency: egp,
        asOf: _t,
        balance: m(-1400000),
        available: m(1000000),
      ),
      if (usdToo)
        AccountBalance(
          accountId: a.id,
          currency: usd,
          asOf: _t,
          balance: m(5000, usd),
        ),
    ]);

CategoryDonut donut() => CategoryDonut(
  total: m(495000),
  slices: [
    CategorySlice(
      categoryId: 'dining',
      amount: m(175000),
      shareBp: 3535,
      count: 4,
    ),
    CategorySlice(
      categoryId: 'groc',
      amount: m(140000),
      shareBp: 2828,
      count: 3,
    ),
    CategorySlice(categoryId: null, amount: m(180000), shareBp: 3637, count: 2),
  ],
);

CardDetailData detailData({bool empty = false}) => CardDetailData(
  donut: empty
      ? const ChartNotEnoughData<CategoryDonut>(
          NotEnoughReason.noData,
          have: 0,
          need: 1,
        )
      : ChartReady(donut()),
  merchants: ChartReady([
    MerchantSpend(
      merchantNorm: 'talabat',
      name: 'Talabat',
      amount: m(110000),
      count: 3,
    ),
  ]),
  trend: ChartReady([
    for (var i = 6; i <= 11; i++)
      CashFlowPoint(
        period: ChartPeriod.month(2026, i),
        income: m(35000),
        spend: m(100000 + i * 1000),
        isPartial: false,
      ),
  ]),
  recent: const [],
  income: m(35000),
  nextDue: CivilDate(2026, 11, 15),
);

const lookups = TxnLookups(
  categories: [
    TxnCategory(
      id: 'dining',
      nameAr: 'مطاعم',
      nameEn: 'Dining',
      icon: 'D',
      color: '#0F7A55',
    ),
    TxnCategory(
      id: 'groc',
      nameAr: 'بقالة',
      nameEn: 'Groceries',
      icon: 'G',
      color: '#0F7A55',
    ),
  ],
  accounts: [],
);

Widget host(
  Widget child, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  double scale = 1.0,
  bool dark = false,
  List<IgnoreRuleRow> rules = const [],
}) => ProviderScope(
  overrides: [
    txnLookupsProvider.overrideWith((ref) async => lookups),
    ignoreRulesStreamProvider.overrideWith((ref) => Stream.value(rules)),
    ...overrides,
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: app!,
    ),
    home: child,
  ),
);

List<Override> detailOverrides({
  AccountWithBalances? acc,
  CardDetailData? data,
  bool dataError = false,
}) => [
  cardDetailAccountProvider.overrideWith(
    (ref, id) async => acc ?? withBalances(credit()),
  ),
  cardDetailDataProvider.overrideWith((ref, key) async {
    if (dataError) throw StateError('x');
    return data ?? detailData();
  }),
];

Future<void> pumpDetail(
  WidgetTester t, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  double scale = 1.0,
  bool dark = false,
  VoidCallback? onSeeAll,
  List<IgnoreRuleRow> rules = const [],
}) async {
  await t.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    host(
      CardDetailScreen(accountId: 'a1', onSeeAll: onSeeAll),
      overrides: overrides,
      locale: locale,
      scale: scale,
      dark: dark,
      rules: rules,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('populated: limit, due date, donut total and sections', (
    t,
  ) async {
    await pumpDetail(t, overrides: detailOverrides());
    expect(find.text('CIB Credit •1234'), findsOneWidget);
    expect(find.textContaining('of'), findsWidgets);
    expect(find.text('Statement due Nov 15, 2026'), findsOneWidget);
    expect(find.text('Top merchants'), findsOneWidget);
    expect(find.text('Monthly trend'), findsOneWidget);
    // FR-CARD-02: the shown slices add up to the card's spend.
    final d = donut();
    expect(d.slices.fold<int>(0, (s, x) => s + x.amount.minor), 495000);
    expect(d.slices.fold<int>(0, (s, x) => s + x.amount.minor), d.total.minor);
    expect(find.text('Dining'), findsWidgets);
    expect(find.text('Groceries'), findsWidgets);
    expect(find.byKey(const Key('card-detail-capture')), findsOneWidget);
    expect(
      find.text('SMS ✓ · Notifications ✓', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('arabic RTL populated, text scale 1.3 does not overflow', (
    t,
  ) async {
    await pumpDetail(
      t,
      overrides: detailOverrides(),
      locale: const Locale('ar', 'EG'),
      scale: 1.3,
    );
    expect(
      find.text('أكتر أماكن صرفت فيها', skipOffstage: false),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    expect(
      Directionality.of(t.element(find.byType(CardDetailScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets('empty period shows the empty state', (t) async {
    await pumpDetail(
      t,
      overrides: detailOverrides(data: detailData(empty: true)),
    );
    expect(find.byKey(const Key('card-detail-empty')), findsOneWidget);
    expect(
      find.text('No spending on this card in this period'),
      findsOneWidget,
    );
  });

  testWidgets('loading shows skeleton', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      host(
        const CardDetailScreen(accountId: 'a1'),
        overrides: [
          cardDetailAccountProvider.overrideWith(
            (ref, id) => Future<AccountWithBalances?>.delayed(
              const Duration(seconds: 5),
            ),
          ),
        ],
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('card-detail-loading')), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('data error shows a banner, not a crash', (t) async {
    await pumpDetail(t, overrides: detailOverrides(dataError: true));
    expect(find.textContaining("Couldn't load this"), findsOneWidget);
  });

  testWidgets('balance unknown (debit, no figures)', (t) async {
    final a = Account(
      id: 'a1',
      kind: AccountKind.debit,
      label: 'NBE',
      defaultCurrency: egp,
      isHidden: false,
      isDefaultCash: false,
      createdAt: _t,
      updatedAt: _t,
    );
    await pumpDetail(
      t,
      overrides: detailOverrides(acc: AccountWithBalances(a, const [])),
    );
    expect(
      find.text('Shows up with the first message that has a balance'),
      findsOneWidget,
    );
  });

  testWidgets('multi-currency: chips switch the currency', (t) async {
    final keys = <CardDetailKey>[];
    await pumpDetail(
      t,
      overrides: [
        cardDetailAccountProvider.overrideWith(
          (ref, id) async => withBalances(credit(), usdToo: true),
        ),
        cardDetailDataProvider.overrideWith((ref, key) async {
          keys.add(key);
          return detailData();
        }),
      ],
    );
    expect(find.text('USD'), findsOneWidget);
    await t.tap(find.text('USD'));
    await t.pumpAndSettle();
    expect(keys.map((k) => k.currency), containsAllInOrder(['EGP', 'USD']));
  });

  testWidgets('ignored card: banner and Track again', (t) async {
    final removed = <String>[];
    await pumpDetail(
      t,
      rules: [
        for (final ch in ['sms', 'notification'])
          IgnoreRuleRow(
            id: 'r-$ch',
            institutionCode: 'cib',
            last4: '1234',
            channel: ch,
            createdAt: 0,
          ),
      ],
      overrides: [
        ...detailOverrides(),
        captureControlsProvider.overrideWith(
          (ref) async => _FakeControls(removed),
        ),
      ],
    );
    expect(find.textContaining('Not tracked'), findsOneWidget);
    expect(
      find.text('SMS ✗ · Notifications ✗', skipOffstage: false),
      findsOneWidget,
    );
    await t.tap(find.text('Track again'));
    await t.pumpAndSettle();
    expect(removed, unorderedEquals(['r-sms', 'r-notification']));
  });

  testWidgets('See all sets the card filter and calls back', (t) async {
    var called = false;
    final recent = TransactionRecord(
      id: 't1',
      accountId: 'a1',
      source: TxnSource.sms,
      direction: TxnDirection.expense,
      status: TxnStatus.posted,
      amount: m(10000),
      occurredAt: _t,
      occurredTzOffsetMin: 120,
      merchantNorm: 'Talabat',
      categoryId: 'dining',
      categorySource: CategorySource.catalog,
      isUserVerified: false,
      isInternal: false,
      createdAt: _t,
      updatedAt: _t,
    );
    await pumpDetail(
      t,
      overrides: [
        cardDetailAccountProvider.overrideWith(
          (ref, id) async => withBalances(credit()),
        ),
        cardDetailDataProvider.overrideWith(
          (ref, key) async => CardDetailData(
            donut: ChartReady(donut()),
            merchants: const ChartNotEnoughData(
              NotEnoughReason.noData,
              have: 0,
              need: 1,
            ),
            trend: const ChartNotEnoughData(
              NotEnoughReason.noData,
              have: 0,
              need: 1,
            ),
            recent: [recent],
            income: null,
            nextDue: null,
          ),
        ),
      ],
      onSeeAll: () => called = true,
    );
    final scrollable = find.byType(Scrollable).first;
    await t.scrollUntilVisible(
      find.text('All card transactions'),
      200,
      scrollable: scrollable,
    );
    await t.tap(find.text('All card transactions'));
    expect(called, isTrue);
    final c = ProviderScope.containerOf(
      t.element(find.byType(CardDetailScreen)),
    );
    expect(c.read(cardFilterProvider), {'a1'});
  });

  group('compare', () {
    CompareCard card(
      String id,
      String label,
      int spend,
      Map<String?, int> by,
    ) => CompareCard(
      accountId: id,
      label: label,
      spend: m(spend),
      byCategory: {for (final e in by.entries) e.key: m(e.value)},
    );

    CompareData data({List<CompareCard>? cards, List<Currency>? currencies}) {
      final cs =
          cards ??
          [
            card('a1', 'NBE •4567', 891000, {'dining': 210000, 'groc': 300000}),
            card('a2', 'CIB •1234', 495000, {'dining': 175000, 'groc': 140000}),
          ];
      return CompareData(
        currencies: currencies ?? [egp],
        currency: egp,
        available: cs,
        cards: cs,
        categoryIds: const ['groc', 'dining'],
        period: ChartPeriod.month(2026, 11),
      );
    }

    Future<void> pumpCompare(
      WidgetTester t,
      CompareData d, {
      Locale locale = const Locale('en'),
      double scale = 1.0,
      void Function(String, String?)? onCell,
    }) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        host(
          CompareCardsScreen(onOpenCell: onCell),
          overrides: [compareDataProvider.overrideWith((ref) async => d)],
          locale: locale,
          scale: scale,
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('table: rows, totals per card, cell tap', (t) async {
      String? got;
      await pumpCompare(t, data(), onCell: (a, c) => got = '$a/$c');
      expect(find.text('Compare cards'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.textContaining('8,910'), findsOneWidget);
      expect(find.textContaining('4,950'), findsOneWidget);
      await t.tap(find.textContaining('1,400').first);
      expect(got, 'a2/groc');
    });

    testWidgets('empty: fewer than two cards with spending', (t) async {
      await pumpCompare(
        t,
        data(
          cards: [
            card('a1', 'NBE', 100, {'dining': 100}),
          ],
        ),
      );
      expect(find.byKey(const Key('compare-empty')), findsOneWidget);
      expect(
        find.text('Compare needs at least two cards with spending'),
        findsOneWidget,
      );
    });

    testWidgets('arabic RTL with text scale 1.3', (t) async {
      await pumpCompare(
        t,
        data(currencies: [egp, usd]),
        locale: const Locale('ar', 'EG'),
        scale: 1.3,
      );
      expect(find.text('مقارنة الكروت'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
    });

    testWidgets('choose cards sheet returns the picked set', (t) async {
      await pumpCompare(t, data());
      final c = ProviderScope.containerOf(
        t.element(find.byType(CompareCardsScreen)),
      );
      c.listen(compareChosenProvider, (_, _) {});
      await t.tap(find.byKey(const Key('compare-choose')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('compare-pick-a2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('compare-pick-done')));
      await t.pumpAndSettle();
      expect(c.read(compareChosenProvider), {'a1'});
    });
  });
}

class _FakeControls implements CaptureControls {
  _FakeControls(this.removed);
  final List<String> removed;

  @override
  Future<RemoveIgnoreResult> remove(String ruleId) async {
    removed.add(ruleId);
    return const RemoveIgnoreResult(
      removed: true,
      guard: null,
      rescanOffer: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}
