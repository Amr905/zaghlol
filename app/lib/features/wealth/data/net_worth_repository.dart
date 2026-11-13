// T-113: assets, liabilities, net worth per unit and snapshots (FR-WLT-01/02/
// 04/05, BR-WLT-01/02, domain-algorithms §11). Reads the T-017 accounts, the
// T-019 assets and the T-112 prices; writes assets and `networth_snapshots`.
// No schema change.
//
// Rules, stated once:
// - Net worth is per unit (currency or gold symbol); [NetWorth] never sums
//   across units. Gold is valued with the price for its karat in
//   `goldCurrency` (A-58) and reported separately from the currency buckets.
// - Assets: account balances (every kind except credit/bnpl, signed), live
//   assets (certificate = principal, A-37; others = manual value, falling
//   back to principal), gold by karat in grams x 1000, coins x 1000.
// - Liabilities: `credit` and `bnpl` account balances (taken as the amount
//   owed; a negative one is an overpayment), live assets flagged
//   `is_liability`, and the remaining active `installment` items
//   ((total - paid) x amount). An installment item whose own credit/bnpl
//   account already carries a balance in that currency is not counted again.
// - Unknown balances (NULL), archived assets and merged accounts are left
//   out; an asset without a value is left out, never counted as zero.
// - Nothing here logs; failures are typed codes.

// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/assets_dao.dart';
import '../../../core/db/daos/prices_dao.dart';
import 'prices_repository.dart';
import '../domain/price_feed.dart';

/// An asset the user is adding. Money is in [currency] (gold and coins have
/// none). [quantityMilli] is grams x 1000 (coins x 1000, funds units x 1000).
final class AssetDraft {
  const AssetDraft({
    required this.type,
    required this.name,
    this.currency,
    this.quantityMilli,
    this.karat,
    this.principal,
    this.rateBp,
    this.payout,
    this.maturityDate,
    this.manualValue,
    this.acquiredAt,
    this.purchasePrice,
    this.isLiability = false,
  });
  final String type;
  final String name;
  final Currency? currency;
  final int? quantityMilli;
  final int? karat;
  final Money? principal;
  final int? rateBp;
  final String? payout;
  final String? maturityDate;
  final Money? manualValue;
  final String? acquiredAt;
  final Money? purchasePrice;
  final bool isLiability;
}

class NetWorthRepository {
  NetWorthRepository({
    required AppDatabase db,
    required PricesRepository prices,
    required DateTime Function() clock,
    required String Function() newId,
  }) : _db = db,
       _prices = prices,
       _assets = AssetsDao(db),
       _snapshots = NetworthSnapshotsDao(db),
       _clock = clock,
       _newId = newId;

  final AppDatabase _db;
  final PricesRepository _prices;
  final AssetsDao _assets;
  final NetworthSnapshotsDao _snapshots;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Adds an asset and returns its id. Refused with [CurrencyMismatch] or a
  /// database constraint code (`guardWrite`) when the draft is not storable.
  Future<String> addAsset(AssetDraft d) async {
    final id = _newId();
    await _assets.insert(
      id: id,
      type: d.type,
      name: d.name,
      currency: d.currency,
      quantityMilli: d.quantityMilli,
      karat: d.karat,
      principal: d.principal,
      rateBp: d.rateBp,
      payout: d.payout,
      maturityDate: d.maturityDate,
      manualValue: d.manualValue,
      acquiredAt: d.acquiredAt,
      purchasePrice: d.purchasePrice,
      isLiability: d.isLiability,
      createdAt: _clock().toUtc().millisecondsSinceEpoch,
    );
    return id;
  }

  Future<List<AssetRow>> liveAssets() => _assets.live();

  Future<int> setManualValue(String id, Money value) =>
      _assets.setManualValue(id, value);

  Future<int> setPrincipal(String id, Money value) =>
      _assets.setPrincipal(id, value);

  Future<int> setQuantity(String id, int quantityMilli) =>
      _assets.setQuantity(id, quantityMilli);

  Future<int> archive(String id) =>
      _assets.archive(id, at: _clock().toUtc().millisecondsSinceEpoch);

  /// Net worth per unit now. Gold is valued in [goldCurrency] (A-58).
  Future<NetWorth> compute({required Currency goldCurrency}) async {
    final money = <MoneyLine>[];
    final gold = <GoldLine>[];

    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.mergedIntoId.isNull())).get();
    final kindOf = {for (final a in accounts) a.id: a.kind};
    final balances = await _db.select(_db.accountBalances).get();
    final carded = <String>{}; // 'accountId|currency' of card/bnpl balances
    for (final b in balances) {
      final kind = kindOf[b.accountId];
      final minor = b.balanceMinor;
      if (kind == null || minor == null) continue;
      final owed = kind == 'credit' || kind == 'bnpl';
      if (owed) carded.add('${b.accountId}|${b.currency}');
      money.add(
        MoneyLine(Money.fromStorage(minor, b.currency), isLiability: owed),
      );
    }

    for (final a in await _assets.live()) {
      final line = _assetLine(a);
      if (line is MoneyLine) money.add(line);
      if (line is GoldLine) gold.add(line);
    }

    final items =
        await (_db.select(_db.recurringItems)..where(
              (r) => r.kind.equals('installment') & r.status.equals('active'),
            ))
            .get();
    for (final r in items) {
      final total = r.totalCount;
      if (total == null) continue;
      if (r.accountId != null &&
          carded.contains('${r.accountId}|${r.currency}')) {
        continue;
      }
      final remaining = total - r.paidCount;
      if (remaining <= 0) continue;
      try {
        money.add(
          MoneyLine(
            Money.fromStorage(r.amountMinor, r.currency).times(remaining),
            isLiability: true,
          ),
        );
      } on MoneyOverflow {
        throw NetWorthOverflow();
      }
    }

    final prices = <String, GoldPrice>{};
    for (final symbol in {for (final g in gold) g.symbol}) {
      final p = await _prices.price(symbol, goldCurrency);
      if (p != null && p.perUnit == perUnitOfSymbol(symbol)) {
        prices[symbol] = GoldPrice(price: p.price, stale: p.stale);
      }
    }
    return computeNetWorth(
      money: money,
      gold: gold,
      goldPrice: (s) => prices[s],
    );
  }

  /// Stores today's snapshot (replacing one taken earlier today). Used on
  /// demand and by [snapshotIfDue]. Returns the number of units stored.
  Future<int> takeSnapshot({
    required CivilDate today,
    required Currency goldCurrency,
  }) async {
    final worth = await compute(goldCurrency: goldCurrency);
    final rows = snapshotRows(worth);
    await _db.transaction(() async {
      for (final r in rows) {
        await _snapshots.upsert(
          takenOn: today.toIso(),
          unit: r.unit,
          assetsMinor: r.assetsMinor,
          liabilitiesMinor: r.liabilitiesMinor,
        );
      }
    });
    return rows.length;
  }

  /// Takes the snapshot when [snapshotDue] says so. Returns true if taken.
  Future<bool> snapshotIfDue({
    required CivilDate today,
    required CivilDate currentCycleStart,
    required Currency goldCurrency,
  }) async {
    final latest = await _latestSnapshotDate();
    if (!snapshotDue(
      last: latest,
      today: today,
      currentCycleStart: currentCycleStart,
    )) {
      return false;
    }
    await takeSnapshot(today: today, goldCurrency: goldCurrency);
    return true;
  }

  /// Net worth history of [unit], oldest first (chart 11).
  Future<List<NetworthSnapshotRow>> history(String unit) =>
      _snapshots.history(unit);

  /// Upcoming certificate interest in `[from, to]`, soonest first (FR-WLT-04).
  /// Each event is in its certificate's own currency.
  Future<List<CertificatePayoutEvent>> upcomingPayouts({
    required CivilDate from,
    required CivilDate to,
  }) async {
    final events = <CertificatePayoutEvent>[];
    for (final a in await _assets.live()) {
      if (a.type != AssetType.certificate || a.isLiability != 0) continue;
      final cur = a.currency;
      final principal = a.principalMinor;
      final rate = a.rateBp;
      final maturity = a.maturityDate == null
          ? null
          : CivilDate.tryParse(a.maturityDate!);
      final payout = PayoutFrequency.fromSlug(a.payout);
      if (cur == null ||
          principal == null ||
          rate == null ||
          maturity == null ||
          payout == null) {
        continue;
      }
      events.addAll(
        certificatePayouts(
          assetId: a.id,
          principal: Money.fromStorage(principal, cur),
          rateBp: rate,
          payout: payout,
          maturity: maturity,
          startDate: a.acquiredAt == null
              ? null
              : CivilDate.tryParse(a.acquiredAt!),
          from: from,
          to: to,
        ),
      );
    }
    events.sort((x, y) {
      final c = x.date.compareTo(y.date);
      return c != 0 ? c : x.assetId.compareTo(y.assetId);
    });
    return events;
  }

  Future<CivilDate?> _latestSnapshotDate() async {
    final row = await _db
        .customSelect(
          'SELECT MAX(taken_on) AS d FROM networth_snapshots',
          readsFrom: {_db.networthSnapshots},
        )
        .getSingle();
    final text = row.read<String?>('d');
    return text == null ? null : CivilDate.tryParse(text);
  }

  static Object? _assetLine(AssetRow a) {
    final liability = a.isLiability != 0;
    if (a.type == AssetType.gold || a.type == AssetType.goldCoin) {
      final q = a.quantityMilli;
      final symbol = a.type == AssetType.goldCoin
          ? GoldSymbols.coin
          : (a.karat == null ? null : GoldSymbols.forKarat(a.karat!));
      if (q == null || symbol == null || liability) return null;
      return GoldLine(symbol, q);
    }
    final cur = a.currency;
    final minor = a.type == AssetType.certificate
        ? a.principalMinor
        : (a.manualValueMinor ?? a.principalMinor);
    if (cur == null || minor == null) return null;
    return MoneyLine(Money.fromStorage(minor, cur), isLiability: liability);
  }
}
