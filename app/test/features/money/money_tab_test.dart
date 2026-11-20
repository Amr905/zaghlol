import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/accounts/presentation/money_overview_provider.dart';
import 'package:zaghlol/features/accounts/presentation/money_tab.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/wealth/data/approx_view_providers.dart';
import 'package:zaghlol/features/wealth/domain/approx_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../support/golden_matrix.dart';
import '../../support/hide_amounts_support.dart';

import 'package:zaghlol/core/ui/z_money_text.dart';

final _egp = Currency.of('EGP');
final _usd = Currency.of('USD');
final _t = DateTime.utc(2026, 11, 1);

Account _acc(
  String id,
  String label, {
  AccountKind kind = AccountKind.debit,
  bool hidden = false,
  String? last4,
  Money? limit,
}) => Account(
  id: id,
  kind: kind,
  label: label,
  defaultCurrency: _egp,
  isHidden: hidden,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
  last4: last4,
  creditLimit: limit,
);

AccountBalance _bal(String id, Currency c, int minor, {int? avail}) =>
    AccountBalance(
      accountId: id,
      currency: c,
      asOf: _t,
      balance: Money(c, minor),
      available: avail == null ? null : Money(c, avail),
    );

class _FakeRepo implements AccountsRepository {
  _FakeRepo(this.items, {this.fail = false});
  final List<AccountWithBalances> items;
  final bool fail;

  @override
  Future<List<AccountWithBalances>> listWithBalances({
    bool includeHidden = false,
  }) async {
    if (fail) throw StateError('x');
    return items;
  }

  @override
  Future<Map<Currency, Money>> totalsByCurrency() async {
    final out = <Currency, Money>{};
    for (final i in items) {
      if (!i.account.kind.isAsset) continue;
      for (final b in i.balances) {
        if (b.balance == null) continue;
        out[b.currency] = out[b.currency] == null
            ? b.balance!
            : out[b.currency]! + b.balance!;
      }
    }
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _full = [
  AccountWithBalances(_acc('a', 'NBE Visa', last4: '4567'), [
    _bal('a', _egp, 1240000),
  ]),
  AccountWithBalances(
    _acc(
      'b',
      'CIB Credit',
      kind: AccountKind.credit,
      last4: '1234',
      limit: Money(_egp, 2000000),
    ),
    [_bal('b', _egp, 500000, avail: 1000000)],
  ),
  AccountWithBalances(_acc('c', 'Wise', kind: AccountKind.multiCurrency), [
    _bal('c', _usd, 120000),
    _bal('c', _egp, 100000),
  ]),
  AccountWithBalances(_acc('d', 'Old', hidden: true), [_bal('d', _egp, 100)]),
  AccountWithBalances(_acc('e', 'Vodafone Cash', kind: AccountKind.wallet), [
    _bal('e', _egp, 35000),
  ]),
  AccountWithBalances(_acc('f', 'My cash', kind: AccountKind.cash), [
    _bal('f', _egp, 20000),
  ]),
];

Future<void> _pump(
  WidgetTester tester, {
  required AccountsRepository repo,
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
  bool gold = false,
  ApproxView approx = const ApproxViewOff(),
  Size size = const Size(390, 1500),
  HideAmountsHarness? hideAmounts,
  bool grouped = true,
  Map<String, CivilDate> due = const {},
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...(hideAmounts ?? HideAmountsHarness()).overrides,
        accountsRepositoryProvider.overrideWith((ref) async => repo),
        moneyGroupByTypeProvider.overrideWith((ref) => Stream.value(grouped)),
        cardDueDatesProvider.overrideWith((ref) async => due),
        approxViewProvider.overrideWith((ref, totals) async => approx),
        if (gold) entitlementStateProvider.overrideWith(() => _GoldNotifier()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const MoneyTab(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _GoldNotifier extends EntitlementNotifier {
  @override
  EntitlementState build() {
    Future.microtask(() => applyVerified(verified: true, status: 'active'));
    return EntitlementState.free;
  }
}

void main() {
  for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
    final l = loc.languageCode;
    group('MoneyTab $l', () {
      testWidgets(
        'data: per-currency hero, rows, hidden entry, locked assets',
        (t) async {
          await _pump(t, repo: _FakeRepo(_full), locale: loc);
          final dir = Directionality.of(t.element(find.byType(MoneyTab)));
          expect(dir, l == 'ar' ? TextDirection.rtl : TextDirection.ltr);
          expect(find.textContaining('NBE Visa'), findsOneWidget);
          expect(find.textContaining('Old'), findsNothing); // hidden
          expect(find.byType(Semantics), findsWidgets);
          expect(t.takeException(), isNull);
          // locked preview for Free
          expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        },
      );

      testWidgets('text scale 1.3 does not overflow', (t) async {
        await _pump(t, repo: _FakeRepo(_full), locale: loc, scale: 1.3);
        expect(t.takeException(), isNull);
      });

      testWidgets('empty', (t) async {
        await _pump(t, repo: _FakeRepo(const []), locale: loc);
        final s = AppLocalizations.of(t.element(find.byType(MoneyTab)));
        expect(find.text(s.accountsOverviewEmptyTitle), findsOneWidget);
        expect(find.text(s.accountsOverviewEmptyAdd), findsOneWidget);
      });

      testWidgets('error', (t) async {
        await _pump(t, repo: _FakeRepo(const [], fail: true), locale: loc);
        final s = AppLocalizations.of(t.element(find.byType(MoneyTab)));
        expect(find.text(s.commonErrorLoadFailed), findsOneWidget);
      });
    });
  }

  testWidgets('T-187: masking on: no digit in any amount, eye in the top bar', (
    t,
  ) async {
    for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      await _pump(t, repo: _FakeRepo(_full), locale: loc, hideAmounts: h);
      expect(find.byKey(const Key('hide-amounts-toggle')), findsOneWidget);
      await expectNoMaskGlyphInSemantics(t);
      final amounts = <String>[
        for (final w in t.widgetList<ZMoneyText>(find.byType(ZMoneyText)))
          '${w.text} ${w.unit ?? ''}',
        for (final w in t.widgetList<Text>(find.byType(Text)))
          if (RegExp(r'EGP|USD|ج\.م').hasMatch(w.data ?? '')) w.data!,
      ];
      expect(amounts, isNotEmpty);
      for (final a in amounts) {
        expect(RegExp(r'[0-9٠-٩]').hasMatch(a), isFalse, reason: a);
      }
    }
  });

  testWidgets('loading shows skeleton', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          accountsRepositoryProvider.overrideWith(
            (ref) => Future<AccountsRepository>.delayed(
              const Duration(seconds: 1),
              () => _FakeRepo(const []),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MoneyTab(),
        ),
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('money-loading')), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('hidden entry hides when none hidden; currencies never summed', (
    t,
  ) async {
    await _pump(t, repo: _FakeRepo(_full.take(3).toList()));
    final s = AppLocalizations.of(t.element(find.byType(MoneyTab)));
    expect(find.text(s.accountsOverviewHiddenEntry), findsNothing);
    // EGP 12,400 + 1,000 = 13,400 (credit is a debt, left out); USD kept apart.
    expect(find.textContaining('13,400'), findsOneWidget);
    expect(find.textContaining('1,200'), findsWidgets);
  });

  testWidgets('hidden entry shown with count', (t) async {
    await _pump(t, repo: _FakeRepo(_full));
    final s = AppLocalizations.of(t.element(find.byType(MoneyTab)));
    expect(find.text(s.accountsOverviewHiddenEntry), findsOneWidget);
  });

  testWidgets('Gold hides the locked preview', (t) async {
    await _pump(t, repo: _FakeRepo(_full), gold: true);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });

  testWidgets('approx: not-included note whenever excluded is non-empty', (
    t,
  ) async {
    await _pump(
      t,
      repo: _FakeRepo(_full),
      approx: ApproxViewOn(
        target: _egp,
        figure: ApproxFigure(Money(_egp, 3290000)),
        excluded: [Currency.of('GBP')],
        rateAsOfMs: null,
        stale: false,
        approximate: true,
      ),
    );
    expect(find.byKey(const Key('approx-not-included')), findsOneWidget);
    expect(find.textContaining('GBP'), findsOneWidget);
  });

  testWidgets('approx: off shows no ≈ line', (t) async {
    await _pump(t, repo: _FakeRepo(_full));
    expect(find.textContaining('≈'), findsNothing);
    expect(find.byKey(const Key('approx-not-included')), findsNothing);
  });

  group('T-197: card type at a glance', () {
    for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
      testWidgets(
        '${loc.languageCode}: every row shows a type chip (text + icon)',
        (t) async {
          await _pump(t, repo: _FakeRepo(_full), locale: loc);
          final l = AppLocalizations.of(t.element(find.byType(MoneyTab)));
          expect(find.text(l.commonAccountTypeDebit), findsOneWidget);
          expect(find.text(l.commonAccountTypeCredit), findsOneWidget);
          expect(find.text(l.commonAccountTypeMultiCurrency), findsOneWidget);
          expect(find.text(l.commonAccountTypeWallet), findsOneWidget);
          expect(find.text(l.commonAccountTypeCash), findsWidgets);
          expect(find.byIcon(Icons.credit_score_rounded), findsOneWidget);
          expect(find.byIcon(Icons.credit_card_rounded), findsOneWidget);
        },
      );

      testWidgets('${loc.languageCode}: grouped sections in order', (t) async {
        await _pump(t, repo: _FakeRepo(_full), locale: loc);
        final l = AppLocalizations.of(t.element(find.byType(MoneyTab)));
        final ys = [
          for (final title in [
            l.accountsGroupBank,
            l.accountsGroupCredit,
            l.accountsGroupWallets,
            l.accountsGroupCash,
          ])
            t.getTopLeft(find.text(title).first).dy,
        ];
        expect(ys, orderedEquals([...ys]..sort()));
      });
    }

    testWidgets('credit: used of limit, bar, due date; debit: balance only', (
      t,
    ) async {
      await _pump(
        t,
        repo: _FakeRepo(_full),
        due: {'b': CivilDate(2026, 11, 28)},
      );
      expect(find.textContaining('10,000'), findsWidgets); // used
      expect(find.textContaining('used of'), findsOneWidget);
      expect(find.byKey(const Key('money-credit-bar')), findsOneWidget);
      expect(find.textContaining('Due '), findsOneWidget);
    });

    testWidgets('hidden amounts: numbers masked, bar and chip stay', (t) async {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      await _pump(
        t,
        repo: _FakeRepo(_full),
        hideAmounts: h,
        due: {'b': CivilDate(2026, 11, 28)},
      );
      expect(find.byKey(const Key('money-credit-bar')), findsOneWidget);
      expect(find.textContaining('10,000'), findsNothing);
      expect(find.textContaining('20,000'), findsNothing);
      expect(find.text('Credit'), findsOneWidget);
    });

    testWidgets('ungrouped: one list, no section titles', (t) async {
      await _pump(t, repo: _FakeRepo(_full), grouped: false);
      final l = AppLocalizations.of(t.element(find.byType(MoneyTab)));
      expect(find.text(l.accountsGroupCredit), findsNothing);
      expect(find.text(l.accountsGroupBank), findsNothing);
      expect(find.text(l.commonAccountTypeCredit), findsOneWidget);
    });

    testWidgets('over the limit: used above limit, full bar, warning tone', (
      t,
    ) async {
      final over = [
        AccountWithBalances(
          _acc(
            'o',
            'Over',
            kind: AccountKind.credit,
            limit: Money(_egp, 1000000),
          ),
          [_bal('o', _egp, 0, avail: -200000)],
        ),
      ];
      await _pump(t, repo: _FakeRepo(over));
      expect(find.textContaining('12,000'), findsWidgets); // used > 10,000
      final bar = t.widget<LinearProgressIndicator>(
        find.byKey(const Key('money-credit-bar')),
      );
      expect(bar.value, 1.0);
      expect(
        bar.color,
        ZColors.of(t.element(find.byType(MoneyTab))).warningText,
      );
    });

    testWidgets('limit and available in different currencies: no bar', (
      t,
    ) async {
      final mixed = [
        AccountWithBalances(
          _acc(
            'm',
            'Mixed',
            kind: AccountKind.credit,
            limit: Money(_egp, 1000000),
          ),
          [_bal('m', _usd, 0, avail: 50000)],
        ),
      ];
      await _pump(t, repo: _FakeRepo(mixed));
      expect(find.byKey(const Key('money-credit-bar')), findsNothing);
      expect(find.textContaining('used of'), findsNothing);
    });

    testWidgets('hidden amounts: the used share is not spoken', (t) async {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      final handle = t.ensureSemantics();
      await _pump(t, repo: _FakeRepo(_full), hideAmounts: h);
      final l = AppLocalizations.of(t.element(find.byType(MoneyTab)));
      expect(find.bySemanticsLabel(RegExp('50%|50٪')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(l.commonAccountTypeCredit)),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('shown amounts: the used share is spoken', (t) async {
      final handle = t.ensureSemantics();
      await _pump(t, repo: _FakeRepo(_full));
      expect(
        find.bySemanticsLabel(RegExp('50% of your limit used')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('toggle writes the persisted choice', (t) async {
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await _pump(t, repo: _FakeRepo(_full), hideAmounts: h);
      await t.tap(find.byKey(const Key('money-group-toggle')));
      await t.pump();
      expect(h.writes[Settings.moneyGroupByType.name], false);
    });
  });
}

/// Used by the golden test.
Future<void> pumpForGolden(WidgetTester tester, GoldenVariant v) => _pump(
  tester,
  repo: _FakeRepo(_full),
  locale: v.locale,
  dark: v.dark,
  scale: v.textScale,
  // Golden fixture: credit with limit, used and a due date, debit, wallet,
  // cash and a multi-currency account (T-197).
  due: {'b': CivilDate(2026, 11, 28)},
);
