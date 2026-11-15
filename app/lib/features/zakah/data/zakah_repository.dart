// T-168: the glue between the T-167 Zakah engine and the stored data
// (FR-ZAK-01..04, BR-ZAK-*). Maps accounts and assets to engine lots in their
// own unit, reads prices from the T-112 store, and keeps the paid records in
// `zakah_ledger`. No schema change.
//
// Rules, stated once:
// - Lots: account balances (not credit/bnpl, positive), live assets that are
//   gold, coins, cash, funds and certificates. Real estate, cars and other
//   assets are not Zakah lots. A lot's own unit is kept; nothing is summed
//   across units here (the engine does the one nisab test).
// - A fully paid cycle stays shown as Paid until the next hawl also completes.
// - Hawl start: the asset's `acquired_at`, else the day it was added; for an
//   account, the day it was added. After a cycle is fully paid the next cycle
//   starts `hawlDays` later (nextHawlStart).
// - Ledger row id: `<lotId>@<cycle start>`. Marking paid writes that row
//   (amount = the due now, paid = the due); marking pending sets paid to 0.
// - Debts: none are read yet (the app has no "short-term debt due now" data);
//   the engine supports them.
// - Nothing is logged.

// ignore_for_file: prefer_initializing_formals

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/assets_dao.dart';
import '../../wealth/data/prices_repository.dart';
import '../../wealth/domain/price_feed.dart';

/// One engine lot plus what the screen needs to show and record it.
final class ZakahLotInfo {
  const ZakahLotInfo({
    required this.lot,
    required this.cycleStart,
    required this.title,
    this.assetId,
    this.karat,
  });
  final ZakahLot lot;

  /// The start of the cycle being counted (after paid cycles).
  final CivilDate cycleStart;

  /// The user's name for the lot (asset name, account label).
  final String title;
  final String? assetId;
  final int? karat;
}

/// A lot with its engine result.
final class ZakahLotView {
  const ZakahLotView({required this.info, required this.result});
  final ZakahLotInfo info;
  final ZakahLotResult result;
  ZakahLot get lot => info.lot;
}

final class ZakahView {
  const ZakahView({
    required this.result,
    required this.lots,
    required this.stale,
    required this.costCurrency,
    required this.rules,
  });
  final ZakahResult result;
  final List<ZakahLotView> lots;

  /// Any price or rate used is stale (EC-34): EGP amounts are approximate.
  final bool stale;
  final Currency costCurrency;
  final ZakahRules rules;

  bool get isEmpty => lots.isEmpty;
}

class ZakahRepository {
  ZakahRepository({
    required AppDatabase db,
    required PricesRepository prices,
    required DateTime Function() clock,
    required Currency costCurrency,
    this.rules = const ZakahRules(),
  }) : _db = db,
       _prices = prices,
       _clock = clock,
       _costCurrency = costCurrency,
       _assets = AssetsDao(db),
       _ledger = ZakahLedgerDao(db);

  final AppDatabase _db;
  final PricesRepository _prices;
  final DateTime Function() _clock;
  final Currency _costCurrency;
  final AssetsDao _assets;
  final ZakahLedgerDao _ledger;
  final ZakahRules rules;

  CivilDate get _today {
    final now = _clock().toLocal();
    return CivilDate(now.year, now.month, now.day);
  }

  static CivilDate _dayOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return CivilDate(d.year, d.month, d.day);
  }

  static String cycleId(String lotId, CivilDate start) =>
      '$lotId@${start.toIso()}';

  /// The Zakah estimate for today.
  Future<ZakahView> compute() async {
    final bases = await _baseLots();
    final ledger = {for (final r in await _ledger.all()) r.id: r};

    final infos = <ZakahLotInfo>[];
    for (final b in bases) {
      var start = b.cycleStart;
      // A fully paid cycle stays on screen as "Paid" until the next hawl
      // after it has also completed; only then does the lot move to the
      // following cycle (nextHawlStart), which is due again at once.
      for (var i = 0; i < 200; i++) {
        final row = ledger[cycleId(b.lot.id, start)];
        if (row == null ||
            row.amountMinor == 0 ||
            row.paidMinor < row.amountMinor ||
            _today.difference(start) < 2 * rules.hawlDays) {
          break;
        }
        start = nextHawlStart(start, rules);
      }
      final paid = ledger[cycleId(b.lot.id, start)]?.paidMinor ?? 0;
      infos.add(
        ZakahLotInfo(
          lot: ZakahLot(
            id: b.lot.id,
            kind: b.lot.kind,
            unit: b.lot.unit,
            amount: b.lot.amount,
            hawlStart: start,
            paid: paid,
          ),
          cycleStart: start,
          title: b.title,
          assetId: b.assetId,
          karat: b.karat,
        ),
      );
    }

    // Prices, prefetched so the engine's callbacks stay synchronous.
    var stale = (await _prices.status()).stale;
    final gold = <String, Money?>{};
    for (final symbol in {
      GoldSymbols.forKarat(24)!,
      for (final i in infos)
        if (i.lot.isGold) i.lot.unit,
    }) {
      final p = await _prices.price(symbol, _costCurrency);
      if (p != null &&
          p.perUnit == perUnitOfSymbol(symbol) &&
          p.price.isPositive) {
        gold[symbol] = p.price;
        stale = stale || p.stale;
      } else {
        gold[symbol] = null;
      }
    }
    final fx = await _prices.fxTable();
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    var fxStale = false;
    final market = ZakahMarket(
      goldPrice: (s) => gold[s],
      convert: (amount, to) {
        if (amount.currency == to) return amount;
        final r = fx.convertApprox(amount, to, nowMs: nowMs);
        if (r is Approx) {
          fxStale = fxStale || r.stale;
          return r.amount;
        }
        return null;
      },
    );
    final result = computeZakah(
      lots: [for (final i in infos) i.lot],
      today: _today,
      market: market,
      costCurrency: _costCurrency,
      rules: rules,
    );
    final byId = {for (final r in result.lots) r.lotId: r};
    return ZakahView(
      result: result,
      lots: [
        for (final i in infos)
          if (byId[i.lot.id] != null)
            ZakahLotView(info: i, result: byId[i.lot.id]!),
      ],
      stale: stale || fxStale,
      costCurrency: _costCurrency,
      rules: rules,
    );
  }

  /// Records [lotView]'s remaining cycle as paid in full (or back to pending).
  /// Per unit: the amount is the lot's own native due (FR-ZAK-04).
  Future<void> setPaid(ZakahLotView lotView, {required bool paid}) async {
    final r = lotView.result;
    if (r.status != ZakahLotStatus.due || r.dueNative <= 0) return;
    final lot = lotView.lot;
    final start = lotView.info.cycleStart;
    await _ledger.upsertCycle(
      id: cycleId(lot.id, start),
      assetId: lotView.info.assetId,
      startHijri: hijriFromCivil(start).toIso(),
      dueOn: r.dueOn.toIso(),
      unit: lot.unit,
      amount: r.dueNative,
      paid: paid ? r.dueNative : 0,
    );
  }

  Future<List<ZakahLotInfo>> _baseLots() async {
    final out = <ZakahLotInfo>[];
    void add(ZakahLotInfo? i) {
      if (i != null) out.add(i);
    }

    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.mergedIntoId.isNull())).get();
    final byId = {for (final a in accounts) a.id: a};
    final balances = await _db.select(_db.accountBalances).get();
    for (final b in balances) {
      final a = byId[b.accountId];
      final minor = b.balanceMinor;
      if (a == null ||
          minor == null ||
          minor <= 0 ||
          a.kind == 'credit' ||
          a.kind == 'bnpl') {
        continue;
      }
      add(
        _make(
          id: 'acct:${a.id}:${b.currency}',
          kind: ZakahLotKind.cash,
          unit: b.currency,
          amount: minor,
          start: _dayOf(a.createdAt),
          title: a.label,
        ),
      );
    }

    for (final a in await _assets.live()) {
      if (a.isLiability != 0) continue;
      final start = a.acquiredAt == null
          ? null
          : CivilDate.tryParse(a.acquiredAt!);
      final day = start ?? _dayOf(a.createdAt);
      switch (a.type) {
        case AssetType.gold:
          final symbol = a.karat == null
              ? null
              : GoldSymbols.forKarat(a.karat!);
          if (symbol != null && a.quantityMilli != null) {
            add(
              _make(
                id: 'asset:${a.id}',
                kind: ZakahLotKind.gold,
                unit: symbol,
                amount: a.quantityMilli!,
                start: day,
                title: a.name,
                assetId: a.id,
                karat: a.karat,
              ),
            );
          }
        case AssetType.goldCoin:
          if (a.quantityMilli != null) {
            add(
              _make(
                id: 'asset:${a.id}',
                kind: ZakahLotKind.gold,
                unit: GoldSymbols.coin,
                amount: a.quantityMilli!,
                start: day,
                title: a.name,
                assetId: a.id,
              ),
            );
          }
        case AssetType.cash:
        case AssetType.stockFund:
        case AssetType.certificate:
          final minor = a.type == AssetType.certificate
              ? a.principalMinor
              : (a.manualValueMinor ?? a.principalMinor);
          if (a.currency != null && minor != null && minor > 0) {
            add(
              _make(
                id: 'asset:${a.id}',
                kind: switch (a.type) {
                  AssetType.cash => ZakahLotKind.cash,
                  AssetType.stockFund => ZakahLotKind.stock,
                  _ => ZakahLotKind.certificate,
                },
                unit: a.currency!,
                amount: minor,
                start: day,
                title: a.name,
                assetId: a.id,
              ),
            );
          }
        default:
          break;
      }
    }
    out.sort((x, y) => x.lot.id.compareTo(y.lot.id));
    return out;
  }

  ZakahLotInfo? _make({
    required String id,
    required ZakahLotKind kind,
    required String unit,
    required int amount,
    required CivilDate start,
    required String title,
    String? assetId,
    int? karat,
  }) {
    try {
      return ZakahLotInfo(
        lot: ZakahLot(
          id: id,
          kind: kind,
          unit: unit,
          amount: amount,
          hawlStart: start,
        ),
        cycleStart: start,
        title: title,
        assetId: assetId,
        karat: karat,
      );
    } on ArgumentError {
      return null; // an unsupported unit or karat: not a Zakah lot
    }
  }
}
