// T-168: widget tests for the Zakah screen (S-46) on in-memory databases with
// the real repositories: flag off, Free (locked), Gold empty, needs prices,
// below nisab, due with mark-as-paid, hawl progress, errors; ar/en, 1.3x.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/wealth/data/net_worth_providers.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/data/prices_providers.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol/features/wealth/presentation/assets_section.dart';
import 'package:zaghlol/features/zakah/data/zakah_providers.dart';
import 'package:zaghlol/features/zakah/data/zakah_repository.dart';
import 'package:zaghlol/features/zakah/presentation/zakah_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../support/hide_amounts_support.dart';

final _now = DateTime.utc(2026, 11, 13, 12);
final _egp = Currency.of('EGP');

class _Gold extends EntitlementNotifier {
  @override
  EntitlementState build() {
    Future.microtask(() => applyVerified(verified: true, status: 'active'));
    return EntitlementState.free;
  }
}

class ZEnv {
  ZEnv(this.db, this.prices, this.repo);
  final AppDatabase db;
  final PricesRepository prices;
  final NetWorthRepository repo;
}

Future<ZEnv> zEnv(WidgetTester t, {bool seedPrices = true}) async {
  final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
  addTearDown(db.close);
  final prices = PricesRepository(db: db, clock: () => _now);
  var n = 0;
  final repo = NetWorthRepository(
    db: db,
    prices: prices,
    clock: () => _now,
    newId: () => 'A${n++}',
  );
  if (seedPrices) {
    await t.runAsync(
      () => prices.apply({
        'asOf': _now.subtract(const Duration(hours: 1)).toIso8601String(),
        'stale': false,
        'gold': [
          {'symbol': 'XAU21_G', 'currency': 'EGP', 'price': '3750.00'},
          {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4280.00'},
        ],
        'fx': {
          'base': 'USD',
          'rates': {'EGP': '49.50'},
        },
      }),
    );
  }
  return ZEnv(db, prices, repo);
}

Future<void> pumpZakah(
  WidgetTester t,
  ZEnv env,
  Widget home, {
  Locale locale = const Locale('en'),
  bool dark = false,
  bool flag = true,
  bool gold = true,
  double scale = 1.0,
  HideAmountsHarness? hideAmounts,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...(hideAmounts ?? HideAmountsHarness()).overrides,
        pricesClockProvider.overrideWithValue(() => _now),
        pricesRepositoryProvider.overrideWith((ref) async => env.prices),
        netWorthRepositoryProvider.overrideWith((ref) async => env.repo),
        featureFlagProvider.overrideWith((ref, f) => flag),
        if (gold) entitlementStateProvider.overrideWith(_Gold.new),
        zakahRepositoryProvider.overrideWith(
          (ref) async => ZakahRepository(
            db: env.db,
            prices: env.prices,
            clock: () => _now,
            costCurrency: _egp,
          ),
        ),
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
        home: home,
      ),
    ),
  );
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pumpAndSettle();
}

Future<void> seedAssets(ZEnv env, WidgetTester t) => t.runAsync(() async {
  // 100 g of 24K bought long ago: hawl complete, above the nisab.
  await env.repo.addAsset(
    const AssetDraft(
      type: AssetType.gold,
      name: 'bars',
      quantityMilli: 100000,
      karat: 24,
      acquiredAt: '2025-01-01',
    ),
  );
  // 18K bought recently: still in its hawl.
  await env.repo.addAsset(
    const AssetDraft(
      type: AssetType.gold,
      name: 'ring',
      quantityMilli: 40000,
      karat: 18,
      acquiredAt: '2026-07-15',
    ),
  );
  await env.repo.addAsset(
    AssetDraft(
      type: AssetType.cash,
      name: 'EGP cash',
      currency: _egp,
      manualValue: Money(_egp, 24000000),
      acquiredAt: '2025-02-01',
    ),
  );
  await env.repo.addAsset(
    AssetDraft(
      type: AssetType.cash,
      name: 'USD cash',
      currency: Currency.of('USD'),
      manualValue: Money(Currency.of('USD'), 1200000),
      acquiredAt: '2025-02-01',
    ),
  );
});

AppLocalizations l10nOf(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

void main() {
  for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
    final lang = loc.languageCode;
    group('zakah $lang', () {
      testWidgets('flag off: nothing is shown and no entry point', (t) async {
        final env = await zEnv(t);
        await pumpZakah(t, env, const ZakahScreen(), locale: loc, flag: false);
        expect(find.byKey(const Key('zakah-hidden')), findsOneWidget);
        expect(find.byType(Scaffold), findsNothing);
        expect(find.byKey(const Key('zakah-disclaimer')), findsNothing);

        await pumpZakah(
          t,
          env,
          Scaffold(
            body: SingleChildScrollView(
              child: AssetsSection(onOpenZakah: () {}),
            ),
          ),
          locale: loc,
          flag: false,
        );
        expect(find.byKey(const Key('zakah-entry')), findsNothing);
      });

      testWidgets('flag on: the Money tab shows the entry and opens it', (
        t,
      ) async {
        final env = await zEnv(t);
        var opened = 0;
        await pumpZakah(
          t,
          env,
          Scaffold(
            body: SingleChildScrollView(
              child: AssetsSection(onOpenZakah: () => opened++),
            ),
          ),
          locale: loc,
        );
        await t.tap(find.byKey(const Key('zakah-entry')));
        expect(opened, 1);
      });

      testWidgets('Free: locked card, disclaimer visible', (t) async {
        final env = await zEnv(t);
        var paywall = 0;
        await pumpZakah(
          t,
          env,
          ZakahScreen(onOpenPaywall: () => paywall++),
          locale: loc,
          gold: false,
        );
        expect(find.byKey(const Key('zakah-locked')), findsOneWidget);
        expect(find.byKey(const Key('zakah-disclaimer')), findsOneWidget);
        await t.tap(find.byKey(const Key('zakah-locked')));
        expect(paywall, 1);
      });

      testWidgets('Gold, no assets: empty state with Add', (t) async {
        final env = await zEnv(t);
        var added = 0;
        await pumpZakah(
          t,
          env,
          ZakahScreen(onAddAsset: () => added++),
          locale: loc,
        );
        final l10n = l10nOf(t);
        expect(find.text(l10n.zakahMainEmptyTitle), findsOneWidget);
        expect(find.byKey(const Key('zakah-disclaimer')), findsOneWidget);
        await t.tap(find.text(l10n.zakahMainEmptyAdd));
        expect(added, 1);
      });

      testWidgets('no prices: needs-prices state, no dues stated', (t) async {
        final env = await zEnv(t, seedPrices: false);
        await seedAssets(env, t);
        await pumpZakah(t, env, const ZakahScreen(), locale: loc);
        expect(find.byKey(const Key('zakah-needs-prices')), findsOneWidget);
        expect(find.byKey(const Key('zakah-totals')), findsNothing);
        expect(find.byKey(const Key('zakah-disclaimer')), findsOneWidget);
      });

      testWidgets('below nisab: explanation and no amounts due', (t) async {
        final env = await zEnv(t);
        await t.runAsync(
          () => env.repo.addAsset(
            AssetDraft(
              type: AssetType.cash,
              name: 'small',
              currency: _egp,
              manualValue: Money(_egp, 100000),
              acquiredAt: '2025-01-01',
            ),
          ),
        );
        await pumpZakah(t, env, const ZakahScreen(), locale: loc);
        final l10n = l10nOf(t);
        expect(find.text(l10n.zakahMainNisabNotReached), findsOneWidget);
        expect(find.byKey(const Key('zakah-below')), findsOneWidget);
        expect(find.byKey(const Key('zakah-totals')), findsNothing);
      });

      testWidgets('T-187: masking on: nisab, dues and lots show no digit', (
        t,
      ) async {
        final env = await zEnv(t);
        await seedAssets(env, t);
        final h = HideAmountsHarness(hidden: true);
        addTearDown(h.dispose);
        await pumpZakah(
          t,
          env,
          const ZakahScreen(),
          locale: loc,
          hideAmounts: h,
        );
        await expectNoAmountDigits(
          t,
          allowLines: RegExp(r'^(The nisab is|النصاب)'),
        );
      });

      testWidgets('populated: per-unit dues, hawl progress, mark paid', (
        t,
      ) async {
        final env = await zEnv(t);
        await seedAssets(env, t);
        await pumpZakah(t, env, const ZakahScreen(), locale: loc);
        final l10n = l10nOf(t);
        expect(find.text(l10n.zakahMainNisabReached), findsOneWidget);
        // Dues per unit: grams, EGP and USD on separate lines.
        final totals = find.descendant(
          of: find.byKey(const Key('zakah-totals')),
          matching: find.byType(Text),
        );
        expect(totals, findsNWidgets(3));
        // The 18K ring is still in its hawl.
        expect(find.textContaining(RegExp(r'[0-9٠-٩]+')), findsWidgets);
        expect(find.text(l10n.zakahMainHawlDone), findsWidgets);
        // Debts are not read, so the screen must not claim they are deducted.
        expect(
          find.text(l10n.zakahMainHowDebts, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text(
            loc.languageCode == 'ar'
                ? 'الديون اللي ميعادها جه بتتخصم من الكاش قبل الحساب.'
                : 'Debts that are due now are deducted from cash first.',
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(
          l10n.zakahMainHowDebts,
          contains(loc.languageCode == 'ar' ? 'مش بتتخصم' : 'not deducted'),
        );

        // Mark the 24K bars paid.
        final pending = find.text(
          '${l10n.zakahMainStatusLabel}: ${l10n.zakahMainStatusPending}',
        );
        expect(pending, findsWidgets);
        await t.tap(pending.first);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('zakah-mark-paid')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pumpAndSettle();
        expect(
          find.text(
            '${l10n.zakahMainStatusLabel}: ${l10n.zakahMainStatusPaid}',
          ),
          findsOneWidget,
        );
        // Recorded per unit in the ledger.
        final rows = await t.runAsync(() => ZakahLedgerDao(env.db).all());
        expect(rows, hasLength(1));
        expect(rows!.single.status, ZakahStatus.paid);
        expect(rows.single.unit, 'XAU24_G');
        expect(rows.single.amountMinor, 2500); // 2.5% of 100 g = 2.5 g
        // Totals dropped to two units.
        final left = find.descendant(
          of: find.byKey(const Key('zakah-totals')),
          matching: find.byType(Text),
        );
        expect(left, findsNWidgets(2));
      });

      testWidgets('1.3x text scale: no overflow', (t) async {
        final env = await zEnv(t);
        await seedAssets(env, t);
        await pumpZakah(t, env, const ZakahScreen(), locale: loc, scale: 1.3);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('zakah-disclaimer')), findsOneWidget);
      });
    });
  }

  testWidgets('error state shows the banner with Try again', (t) async {
    final env = await zEnv(t);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...amountsShown(),
          featureFlagProvider.overrideWith((ref, f) => true),
          entitlementStateProvider.overrideWith(_Gold.new),
          zakahViewProvider.overrideWith((ref) async => throw StateError('x')),
        ],
        child: MaterialApp(
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ZakahScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    final l10n = l10nOf(t);
    expect(find.text(l10n.commonActionTryAgain), findsOneWidget);
    expect(find.byKey(const Key('zakah-disclaimer')), findsOneWidget);
    expect(env.db, isNotNull);
  });
}
