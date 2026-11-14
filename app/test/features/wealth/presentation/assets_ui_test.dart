// T-121: widget tests for the assets section (S-40), Add asset (S-44) and
// Prices (S-45) on in-memory databases with the real repositories.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/wealth/data/net_worth_providers.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/data/prices_providers.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol/features/wealth/presentation/add_asset_screen.dart';
import 'package:zaghlol/features/wealth/presentation/assets_section.dart';
import 'package:zaghlol/features/wealth/presentation/prices_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _now = DateTime.utc(2026, 11, 13, 12);
final _egp = Currency.of('EGP');

class _Gold extends EntitlementNotifier {
  @override
  EntitlementState build() {
    Future.microtask(() => applyVerified(verified: true, status: 'active'));
    return EntitlementState.free;
  }
}

class _Env {
  _Env(this.db, this.prices, this.repo);
  final AppDatabase db;
  final PricesRepository prices;
  final NetWorthRepository repo;
}

Future<_Env> _env(
  WidgetTester t, {
  DateTime? priceAsOf,
  bool seed = true,
}) async {
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
  if (seed) {
    await t.runAsync(
      () => prices.apply({
        'asOf': (priceAsOf ?? _now.subtract(const Duration(hours: 1)))
            .toIso8601String(),
        'stale': false,
        'gold': [
          {'symbol': 'XAU21_G', 'currency': 'EGP', 'price': '3750.00'},
          {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4280.00'},
        ],
        'fx': {
          'base': 'USD',
          'rates': {'EGP': '49.50', 'SAR': '3.75'},
        },
      }),
    );
  }
  return _Env(db, prices, repo);
}

Future<void> _pump(
  WidgetTester t,
  _Env env,
  Widget home, {
  Locale locale = const Locale('en'),
  bool dark = false,
  bool gold = true,
  double scale = 1.0,
  List<GoldCapability>? paywall,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        pricesClockProvider.overrideWithValue(() => _now),
        pricesRepositoryProvider.overrideWith((ref) async => env.prices),
        netWorthRepositoryProvider.overrideWith((ref) async => env.repo),
        if (gold) entitlementStateProvider.overrideWith(_Gold.new),
        if (paywall != null)
          paywallTriggerProvider.overrideWithValue(paywall.add),
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

Widget _section({
  VoidCallback? add,
  VoidCallback? prices,
  VoidCallback? paywall,
}) => Scaffold(
  body: SingleChildScrollView(
    child: AssetsSection(
      onAddAsset: add,
      onOpenPrices: prices,
      onOpenPaywall: paywall,
    ),
  ),
);

AppLocalizations _l(WidgetTester t, Type of) =>
    AppLocalizations.of(t.element(find.byType(of).first));

Future<void> _seedAssets(_Env env, WidgetTester t) => t.runAsync(() async {
  await env.repo.addAsset(
    const AssetDraft(
      type: AssetType.gold,
      name: 'XAU21_G',
      quantityMilli: 24000,
      karat: 21,
    ),
  );
  await env.repo.addAsset(
    AssetDraft(
      type: AssetType.certificate,
      name: 'NBE',
      currency: _egp,
      principal: Money(_egp, 16300000),
      rateBp: 2700,
      payout: CertificatePayout.monthly,
      maturityDate: '2027-06-13',
    ),
  );
  await env.repo.addAsset(
    AssetDraft(
      type: AssetType.cash,
      name: 'GBP',
      currency: Currency.of('GBP'),
      manualValue: Money(Currency.of('GBP'), 30000),
    ),
  );
  await env.repo.addAsset(
    AssetDraft(
      type: AssetType.realEstate,
      name: 'Flat',
      currency: _egp,
      manualValue: Money(_egp, 250000000),
    ),
  );
});

void main() {
  for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
    final lang = loc.languageCode;
    group('assets section $lang', () {
      testWidgets('Free: locked preview, tap opens the paywall hook', (
        t,
      ) async {
        final env = await _env(t);
        var opened = 0;
        await _pump(
          t,
          env,
          _section(paywall: () => opened++),
          locale: loc,
          gold: false,
        );
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        await t.tap(find.byIcon(Icons.lock_outline_rounded));
        expect(opened, 1);
      });

      testWidgets('Gold empty: one line with Add asset', (t) async {
        final env = await _env(t);
        var added = 0;
        await _pump(t, env, _section(add: () => added++), locale: loc);
        final l10n = _l(t, AssetsSection);
        expect(find.text(l10n.wealthOverviewAssetsEmpty), findsOneWidget);
        await t.tap(find.text(l10n.wealthAssetTitleAdd));
        expect(added, 1);
      });

      testWidgets(
        'Gold rows: gold native unit, cert payout, no-rate, estimate',
        (t) async {
          final env = await _env(t);
          await _seedAssets(env, t);
          await _pump(t, env, _section(), locale: loc);
          final l10n = _l(t, AssetsSection);
          // gold row at the 21K price: 24 g x 3,750 = 90,000
          expect(
            find.textContaining(
              l10n.wealthOverviewGoldTitle(lang == 'ar' ? '٢١' : '21'),
            ),
            findsWidgets,
          );
          expect(
            find.textContaining(lang == 'ar' ? '٩٠٬٠٠٠' : '90,000'),
            findsOneWidget,
          );
          expect(
            find.text(l10n.wealthOverviewCertTitle('NBE')),
            findsOneWidget,
          );
          expect(
            find.textContaining(l10n.wealthOverviewNoRate('GBP')),
            findsOneWidget,
          );
          expect(find.text(l10n.wealthOverviewManualValue), findsOneWidget);
          expect(find.text(l10n.commonBadgeStale), findsNothing);
          expect(t.takeException(), isNull);
        },
      );

      testWidgets('stale gold price shows the stale badge', (t) async {
        final env = await _env(
          t,
          priceAsOf: _now.subtract(const Duration(hours: 30)),
        );
        await _seedAssets(env, t);
        await _pump(t, env, _section(), locale: loc);
        expect(
          find.text(_l(t, AssetsSection).commonBadgeStale),
          findsOneWidget,
        );
      });

      testWidgets('text scale 1.3 and dark do not overflow', (t) async {
        final env = await _env(t);
        await _seedAssets(env, t);
        await _pump(t, env, _section(), locale: loc, scale: 1.3, dark: true);
        expect(t.takeException(), isNull);
      });
    });

    group('add asset $lang', () {
      testWidgets('Free: locked and the paywall hook fires; no form', (
        t,
      ) async {
        final env = await _env(t);
        final hooks = <GoldCapability>[];
        await _pump(
          t,
          env,
          const AddAssetScreen(),
          locale: loc,
          gold: false,
          paywall: hooks,
        );
        expect(hooks, [GoldCapability.investmentAssets]);
        expect(find.byKey(const Key('asset-locked')), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });

      testWidgets('Save without a type shows the type error', (t) async {
        final env = await _env(t);
        await _pump(t, env, const AddAssetScreen(), locale: loc);
        final l10n = _l(t, AddAssetScreen);
        await t.tap(find.text(l10n.commonActionSave));
        await t.pumpAndSettle();
        expect(find.text(l10n.wealthAssetErrorType), findsOneWidget);
      });

      testWidgets(
        'gold 24.5 g typed in Arabic-Indic digits is stored exactly',
        (t) async {
          final env = await _env(t);
          var saved = 0;
          await _pump(
            t,
            env,
            AddAssetScreen(onSaved: () => saved++),
            locale: loc,
          );
          final l10n = _l(t, AddAssetScreen);
          await t.tap(find.text(l10n.commonAssetTypeGold));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField).first, '٢٤٫٥');
          await t.tap(find.text(l10n.commonActionSave));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pumpAndSettle();
          expect(saved, 1);
          final rows = await t.runAsync(env.repo.liveAssets);
          expect(rows!.single.quantityMilli, 24500);
          expect(rows.single.karat, 21);
        },
      );

      testWidgets('certificate with a bad rate shows the rate error', (
        t,
      ) async {
        final env = await _env(t);
        await _pump(t, env, const AddAssetScreen(), locale: loc);
        final l10n = _l(t, AddAssetScreen);
        await t.tap(find.text(l10n.commonAssetTypeCertificate));
        await t.pumpAndSettle();
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), 'NBE');
        await t.enterText(fields.at(1), '1000');
        await t.enterText(fields.at(2), '101');
        await t.tap(find.text(l10n.commonActionSave));
        await t.pumpAndSettle();
        expect(find.text(l10n.wealthAssetErrorRate('100')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('text scale 1.3 on the form does not overflow', (t) async {
        final env = await _env(t);
        await _pump(t, env, const AddAssetScreen(), locale: loc, scale: 1.3);
        await t.tap(
          find.text(_l(t, AddAssetScreen).commonAssetTypeCertificate),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    });

    group('prices $lang', () {
      testWidgets('never fetched: explainer and Enter manually', (t) async {
        final env = await _env(t, seed: false);
        await _pump(t, env, const PricesScreen(), locale: loc);
        final l10n = _l(t, PricesScreen);
        expect(find.text(l10n.wealthPricesNeverTitle), findsOneWidget);
        expect(find.text(l10n.wealthPricesEnterManually), findsOneWidget);
      });

      testWidgets('data: gold rows, updated line, no stale badge', (t) async {
        final env = await _env(t);
        await _pump(t, env, const PricesScreen(), locale: loc);
        final l10n = _l(t, PricesScreen);
        expect(find.text(l10n.wealthPricesGoldSection), findsOneWidget);
        expect(find.text(l10n.wealthPricesOverride), findsNWidgets(3));
        expect(find.text(l10n.commonBadgeStale), findsNothing);
        expect(
          find.textContaining(lang == 'ar' ? '٤٬٢٨٠' : '4,280'),
          findsOneWidget,
        );
      });

      testWidgets('stale prices show the badge', (t) async {
        final env = await _env(
          t,
          priceAsOf: _now.subtract(const Duration(hours: 30)),
        );
        await _pump(t, env, const PricesScreen(), locale: loc);
        expect(find.text(_l(t, PricesScreen).commonBadgeStale), findsWidgets);
      });

      testWidgets('override then reset', (t) async {
        final env = await _env(t);
        await _pump(t, env, const PricesScreen(), locale: loc);
        final l10n = _l(t, PricesScreen);
        await t.tap(find.text(l10n.wealthPricesOverride).first);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '٤٣٠٠');
        await t.tap(find.text(l10n.wealthPricesOverrideUse));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pumpAndSettle();
        expect(find.text(l10n.wealthPricesYours), findsOneWidget);
        expect(find.text(l10n.wealthPricesReset), findsOneWidget);
        await t.tap(find.text(l10n.wealthPricesReset));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pumpAndSettle();
        expect(find.text(l10n.wealthPricesYours), findsNothing);
      });

      testWidgets('override rejects zero', (t) async {
        final env = await _env(t);
        await _pump(t, env, const PricesScreen(), locale: loc);
        final l10n = _l(t, PricesScreen);
        await t.tap(find.text(l10n.wealthPricesOverride).first);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '0');
        await t.tap(find.text(l10n.wealthPricesOverrideUse));
        await t.pumpAndSettle();
        expect(find.text(l10n.commonValidationAmountRequired), findsOneWidget);
      });
    });
  }
}

/// Used by the golden test.
Future<void> pumpScreenForGolden(
  WidgetTester t,
  String screen,
  // ignore: library_private_types_in_public_api
  dynamic variant,
) async {
  final env = await _env(t);
  await _seedAssets(env, t);
  final Widget home = switch (screen) {
    'add_asset' => const AddAssetScreen(),
    'prices' => const PricesScreen(),
    _ => _section(),
  };
  await _pump(
    t,
    env,
    home,
    locale: variant.locale as Locale,
    dark: variant.dark as bool,
  );
}
