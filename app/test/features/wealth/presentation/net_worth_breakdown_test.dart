// T-199: the breakdown screen (D-75). Synthetic data, provider overrides; the
// set-balance write goes to an in-memory database.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart' as keys;
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/presentation/net_worth_breakdown_providers.dart';
import 'package:zaghlol/features/wealth/presentation/net_worth_breakdown_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/golden_matrix.dart';
import '../../../support/hide_amounts_support.dart';

final _egp = Currency.of('EGP');
final _usd = Currency.of('USD');
final _t0 = DateTime.utc(2026, 11, 18, 9);
final _now = DateTime.utc(2026, 11, 20, 9);

BreakdownLine _acct(
  String id,
  String label,
  String kind,
  int? minor, {
  String? inst,
  String? last4,
  Currency? cur,
  TxnTotals totals = const TxnTotals(),
  AnchorBasis? basis,
}) {
  final c = cur ?? _egp;
  final liability = kind == 'credit' || kind == 'bnpl';
  return resolveAccountLine(
    accountId: id,
    label: label,
    accountKind: kind,
    currency: c,
    isLiability: liability,
    now: _now,
    institutionCode: inst,
    last4: last4,
    totals: totals,
    anchor: minor == null
        ? null
        : BalanceAnchor(
            amount: Money(c, minor),
            asOf: _t0,
            userEntered: false,
            basis: basis,
          ),
  );
}

NetWorthBreakdown _fixture() {
  final lines = <BreakdownLine>[
    _acct('a1', 'CIB', 'debit', 1000000, inst: 'cib', last4: '1111'),
    _acct(
      'a2',
      'CIB',
      'account',
      500000,
      inst: 'cib',
      last4: '2222',
      totals: const TxnTotals(cashEffectMinor: -20000, count: 2),
    ),
    _acct('n1', 'NBE', 'debit', 250000, inst: 'nbe', last4: '3333'),
    _acct('c1', 'CIB Credit', 'credit', 300000, inst: 'cib', last4: '4444'),
    _acct('u1', 'Vodafone Cash', 'wallet', null),
    _acct('w1', 'Wise', 'multi_currency', 120000, cur: _usd),
    BreakdownLine(
      group: BreakdownGroup.assets,
      unit: 'EGP',
      label: 'Cert',
      source: BalanceSource.asset,
      amount: Money(_egp, 2000000),
    ),
  ];
  return NetWorthBreakdown(
    lines: lines,
    units: buildUnitBreakdowns(lines),
    worth: computeNetWorth(money: moneyLinesOf(lines)),
  );
}

Future<void> _pump(
  WidgetTester t, {
  Locale locale = const Locale('en'),
  bool dark = false,
  HideAmountsHarness? hide,
  AppDatabase? db,
  NetWorthBreakdown? data,
  ValueChanged<List<String>>? onOpen,
  Size size = const Size(390, 2200),
}) async {
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...(hide ?? HideAmountsHarness()).overrides,
        netWorthBreakdownProvider.overrideWith(
          (ref) async => data ?? _fixture(),
        ),
        if (db != null) appDatabaseProvider.overrideWith((ref) async => db),
      ],
      child: MaterialApp(
        locale: locale,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NetWorthBreakdownScreen(onOpenTransactions: onOpen),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> pumpForGolden(WidgetTester t, GoldenVariant v) => _pump(
  t,
  locale: v.locale,
  dark: v.dark,
  hide: null,
  size: const Size(390, 1900),
);

NetWorthBreakdown _goldFixture() {
  final lines = <BreakdownLine>[
    const BreakdownLine(
      group: BreakdownGroup.assets,
      unit: 'XAU21_G',
      label: 'Gold',
      source: BalanceSource.asset,
      quantityMilli: 24000,
    ),
    const BreakdownLine(
      group: BreakdownGroup.assets,
      unit: 'XAU_COIN8G',
      label: 'Coins',
      source: BalanceSource.asset,
      quantityMilli: 3000,
    ),
  ];
  return NetWorthBreakdown(
    lines: lines,
    units: buildUnitBreakdowns(lines),
    worth: computeNetWorth(money: const [], gold: goldLinesOf(lines)),
  );
}

void main() {
  testWidgets('en: groups, bank totals, sources, excluded line', (t) async {
    await _pump(t);
    final l = AppLocalizations.of(
      t.element(find.byType(NetWorthBreakdownScreen)),
    );
    expect(find.text(l.networthTitle), findsOneWidget);
    expect(find.text(l.networthGroupAccounts), findsWidgets);
    expect(find.text(l.networthGroupAssets), findsWidgets);
    expect(find.text(l.networthGroupLiabilities), findsOneWidget);
    expect(find.text(l.networthGroupExcluded), findsOneWidget);
    // CIB: two accounts, header total = 10,000 + (5,000 - 200) = 14,800.00
    expect(find.textContaining('14,800'), findsOneWidget);
    // EGP net = 10,000 + 4,800 + 2,500 + 20,000 - 3,000 = 34,300
    expect(find.textContaining('34,300'), findsOneWidget);
    // USD kept apart
    expect(find.textContaining('1,200'), findsWidgets);
    // sources
    expect(find.textContaining('Bank message'), findsWidgets);
    expect(find.textContaining('Worked out from transactions'), findsOneWidget);
    expect(find.textContaining('Bank message (amount owed)'), findsOneWidget);
    expect(find.text(l.networthSrcAsset), findsOneWidget);
    expect(find.text(l.networthSrcUnknown), findsOneWidget);
    expect(find.text(l.networthSetBalance), findsOneWidget);
  });

  testWidgets('ar renders RTL with Arabic source words', (t) async {
    await _pump(t, locale: const Locale('ar', 'EG'));
    expect(
      Directionality.of(t.element(find.byType(NetWorthBreakdownScreen))),
      TextDirection.rtl,
    );
    expect(find.textContaining('من رسالة البنك'), findsWidgets);
    expect(find.textContaining('محسوب من الحركات'), findsOneWidget);
    expect(find.text('مش معروف — حط الرصيد'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a bank opens its accounts; one account opens itself', (
    t,
  ) async {
    final opened = <List<String>>[];
    await _pump(t, onOpen: opened.add);
    await t.tap(find.byKey(const Key('networth-bank-cib')));
    await t.pump();
    expect(opened.last, ['a1', 'a2']);
    await t.tap(find.textContaining('NBE'));
    await t.pump();
    expect(opened.last, ['n1']);
  });

  testWidgets('hidden amounts: no digit in any amount, text stays', (t) async {
    final h = HideAmountsHarness(hidden: true);
    addTearDown(h.dispose);
    await _pump(t, hide: h);
    await expectNoAmountDigits(t);
    await expectNoMaskGlyphInSemantics(t);
  });

  testWidgets('set balance: stores a user entry, refuses a bad amount', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    await _pump(t, db: db);
    final l = AppLocalizations.of(
      t.element(find.byType(NetWorthBreakdownScreen)),
    );
    await t.tap(find.text(l.networthSetBalance));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('networth-amount')), 'abc');
    await t.tap(find.byKey(const Key('networth-save')));
    await t.pumpAndSettle();
    expect(find.text(l.networthSheetInvalid), findsOneWidget);
    expect(await SettingsDao(db).read('balance.opening'), isNull);

    await t.enterText(find.byKey(const Key('networth-amount')), '١٢٥٠٫٥٠');
    await t.tap(find.byKey(const Key('networth-save')));
    await t.pumpAndSettle();
    final k = keys.Settings.openingBalances;
    final stored = k.parse(await SettingsDao(db).read(k.name));
    expect(stored.of('u1', 'EGP')!.amount.minor, 125050);
    expect(find.byKey(const Key('networth-amount')), findsNothing);
  });

  testWidgets('gold stays in grams and coins', (t) async {
    await _pump(t, data: _goldFixture());
    expect(find.textContaining('24'), findsWidgets);
    expect(find.textContaining('g'), findsWidgets);
  });

  testWidgets('gold amounts are masked when hidden', (t) async {
    final h = HideAmountsHarness(hidden: true);
    addTearDown(h.dispose);
    await _pump(t, data: _goldFixture(), hide: h);
    await expectNoAmountDigits(t);
  });

  testWidgets('empty: a note, no sections', (t) async {
    final empty = NetWorthBreakdown(
      lines: const [],
      units: const [],
      worth: computeNetWorth(money: const []),
    );
    await _pump(t, data: empty);
    final l = AppLocalizations.of(
      t.element(find.byType(NetWorthBreakdownScreen)),
    );
    expect(find.text(l.networthEmpty), findsOneWidget);
  });
}
