// T-121: read models for the Money tab assets section (S-40) and the Prices
// screen (S-45). Reads the T-113 net worth and T-112 prices repositories;
// widgets never touch the database.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/assets_dao.dart';
import '../data/net_worth_providers.dart';
import '../data/prices_providers.dart';
import '../data/prices_repository.dart';
import '../domain/price_feed.dart';

/// Gold is valued in EGP (A-58).
final Currency goldCurrency = Currency.of('EGP');

/// How far ahead the next certificate payout is looked up.
const int payoutLookAheadDays = 400;

/// One row of the assets section.
final class AssetRowView {
  const AssetRowView({
    required this.row,
    this.goldValue,
    this.goldStale = false,
    this.nextPayout,
    this.noRate = false,
  });

  final AssetRow row;

  /// Gold at the current price (null: no price, shown in grams only).
  final Money? goldValue;
  final bool goldStale;
  final CertificatePayoutEvent? nextPayout;

  /// Foreign cash with no rate to EGP yet (EC-35).
  final bool noRate;
}

final class AssetsOverview {
  const AssetsOverview({
    required this.rows,
    required this.worth,
    required this.status,
  });
  final List<AssetRowView> rows;
  final NetWorth worth;
  final PricesStatus status;

  /// Gold units (karat symbols and coins) in their native unit, never summed.
  List<UnitNetWorth> get goldUnits => [
    for (final u in worth.units)
      if (u.isGold && u.netMinor > 0) u,
  ];
}

DateTime _toLocalDate(DateTime now) => DateTime(now.year, now.month, now.day);

final assetsOverviewProvider = FutureProvider<AssetsOverview>((ref) async {
  final repo = await ref.watch(netWorthRepositoryProvider.future);
  final prices = await ref.watch(pricesRepositoryProvider.future);
  final now = ref.watch(pricesClockProvider)().toLocal();
  final today = _toLocalDate(now);
  final from = CivilDate(today.year, today.month, today.day);
  final end = today.add(const Duration(days: payoutLookAheadDays));
  final to = CivilDate(end.year, end.month, end.day);

  final assets = await repo.liveAssets();
  final worth = await repo.compute(goldCurrency: goldCurrency);
  final payouts = await repo.upcomingPayouts(from: from, to: to);
  final next = <String, CertificatePayoutEvent>{};
  for (final p in payouts) {
    next.putIfAbsent(p.assetId, () => p);
  }

  final rows = <AssetRowView>[];
  for (final a in assets) {
    if (a.type == AssetType.gold || a.type == AssetType.goldCoin) {
      final symbol = a.type == AssetType.goldCoin
          ? GoldSymbols.coin
          : (a.karat == null ? null : GoldSymbols.forKarat(a.karat!));
      final q = a.quantityMilli;
      Money? value;
      var stale = false;
      if (symbol != null && q != null && q > 0) {
        final p = await prices.price(symbol, goldCurrency);
        if (p != null &&
            p.perUnit == perUnitOfSymbol(symbol) &&
            p.price.isPositive) {
          try {
            value = valueGold(p.price, q);
            stale = p.stale;
          } on MoneyOverflow {
            value = null;
          }
        }
      }
      rows.add(AssetRowView(row: a, goldValue: value, goldStale: stale));
    } else if (a.type == AssetType.cash) {
      final cur = a.currency == null ? null : Currency.tryOf(a.currency!);
      var noRate = false;
      if (cur != null && cur != goldCurrency) {
        final r = await prices.convertApprox(Money(cur, 0), goldCurrency);
        noRate = r is MissingRate;
      }
      rows.add(AssetRowView(row: a, noRate: noRate));
    } else {
      rows.add(AssetRowView(row: a, nextPayout: next[a.id]));
    }
  }
  return AssetsOverview(
    rows: rows,
    worth: worth,
    status: await prices.status(),
  );
}, name: 'assetsOverviewProvider');

/// One gold price line on S-45.
final class GoldPriceRow {
  const GoldPriceRow({required this.karat, required this.symbol, this.price});
  final int karat;
  final String symbol;
  final ResolvedPrice? price;
}

/// One currency line on S-45: the value of one unit in EGP.
final class FxRow {
  const FxRow({required this.currency, this.value, this.stale = false});
  final Currency currency;
  final Money? value;
  final bool stale;
}

final class PricesScreenData {
  const PricesScreenData({
    required this.status,
    required this.gold,
    required this.fx,
  });
  final PricesStatus status;
  final List<GoldPriceRow> gold;
  final List<FxRow> fx;

  bool get neverFetched =>
      status.backendAsOfMs == null && gold.every((g) => g.price == null);
}

const List<int> priceKarats = [24, 21, 18];

final pricesScreenProvider = FutureProvider<PricesScreenData>((ref) async {
  final prices = await ref.watch(pricesRepositoryProvider.future);
  final nw = await ref.watch(netWorthRepositoryProvider.future);
  final gold = <GoldPriceRow>[];
  for (final k in priceKarats) {
    final s = GoldSymbols.forKarat(k)!;
    gold.add(
      GoldPriceRow(
        karat: k,
        symbol: s,
        price: await prices.price(s, goldCurrency),
      ),
    );
  }
  // Currencies the user holds, then the featured ones (never EGP itself).
  final codes = <String>{};
  for (final a in await nw.liveAssets()) {
    if (a.currency != null) codes.add(a.currency!);
  }
  codes.addAll(Currency.featuredCodes);
  codes.remove(goldCurrency.code);
  final fx = <FxRow>[];
  for (final code in codes) {
    final cur = Currency.of(code);
    final one = Money(cur, BigInt.from(10).pow(cur.exponent).toInt());
    final r = await prices.convertApprox(one, goldCurrency);
    fx.add(
      r is Approx
          ? FxRow(currency: cur, value: r.amount, stale: r.stale)
          : FxRow(currency: cur),
    );
  }
  return PricesScreenData(status: await prices.status(), gold: gold, fx: fx);
}, name: 'pricesScreenProvider');
