// T-112: the local prices and FX store (FR-WLT-03). Reuses the T-019 tables
// and DAO (no schema change). The sync (T-143) hands the `prices` block of
// `POST /v1/sync` to [PricesRepository.apply]; [refresh] pulls through a
// narrow port the BackendClient (T-141) will implement, like the flags (T-025).
//
// Rules:
// - A block is parsed strictly; any defect rejects all of it and keeps what
//   is stored. A block older than the stored data is a replay: ignored.
// - Quotes, rates and the backend's `stale` flag are written in ONE
//   transaction, so a reader never sees a half-applied block.
// - Manual overrides are separate rows (`source = 'manual'`); the apply never
//   touches them and they win until cleared.
// - Stale data is returned labelled, never dropped and never relabelled fresh.
// - Rates convert nothing stored: [convertApprox] is the ≈ view only.
// - Nothing is logged; failures carry codes only.

// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/prices_dao.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/db/money_columns.dart';
import '../domain/price_feed.dart';

/// `secure_state` key of the backend's `stale` flag for the last block (a
/// cache; not part of any backup).
const String pricesReportedStaleKey = 'prices.reported_stale';

/// The backend's raw `prices` block (untrusted until parsed).
final class RemotePrices {
  const RemotePrices(this.block);
  final Object? block;
}

/// The failure of a [RemotePricesSource]. Code only.
final class PricesUnavailable implements Exception {
  const PricesUnavailable();
  @override
  String toString() => 'PricesUnavailable';
}

/// The narrow port to the backend (BackendClient, T-141). Throws
/// [PricesUnavailable] when offline, unverified or refused.
abstract interface class RemotePricesSource {
  Future<RemotePrices> fetch();
}

enum PricesApplyResult {
  /// Stored.
  applied,

  /// Malformed or a replay of older data: nothing changed.
  rejected,

  /// No source, or it was unavailable: nothing changed.
  unavailable,
}

/// What the store holds, for the "last updated" line and the stale banner.
final class PricesStatus {
  const PricesStatus({
    required this.backendAsOfMs,
    required this.stale,
    required this.hasManualOverride,
  });

  /// When the newest backend data is from; null if never synced.
  final int? backendAsOfMs;

  /// True when synced backend data is stale. Never synced is not stale
  /// (there is nothing to label; [backendAsOfMs] is null).
  final bool stale;
  final bool hasManualOverride;
}

class PricesRepository {
  PricesRepository({
    required AppDatabase db,
    required DateTime Function() clock,
    RemotePricesSource? remote,
  }) : _db = db,
       _dao = PricesDao(db),
       _secure = SecureStateDao(db),
       _clock = clock,
       _remote = remote;

  final AppDatabase _db;
  final PricesDao _dao;
  final SecureStateDao _secure;
  final DateTime Function() _clock;
  final RemotePricesSource? _remote;

  int get _nowMs => _clock().toUtc().millisecondsSinceEpoch;

  /// Applies a raw `prices` block. Never throws for bad input.
  Future<PricesApplyResult> apply(Object? raw) async {
    final PriceBlock block;
    try {
      block = parsePriceBlock(raw);
    } on PricesRejected {
      return PricesApplyResult.rejected;
    }
    return _db.transaction(() async {
      final stored = await _newestBackendAsOf();
      if (stored != null && block.asOfMs < stored) {
        return PricesApplyResult.rejected;
      }
      await _dao.replaceBackendQuotes([
        for (final g in block.gold)
          (
            symbol: g.symbol,
            price: g.price,
            perUnit: g.perUnit,
            asOf: block.asOfMs,
          ),
      ]);
      await _dao.replaceRates([
        for (final e in block.fxRates.entries)
          (
            base: block.fxBase,
            quote: e.key,
            rateE9: e.value,
            asOf: block.asOfMs,
          ),
      ]);
      await _secure.write(
        pricesReportedStaleKey,
        Uint8List.fromList([block.reportedStale ? 1 : 0]),
        at: _nowMs,
      );
      return PricesApplyResult.applied;
    });
  }

  /// Pulls the block through the port and applies it.
  Future<PricesApplyResult> refresh() async {
    final remote = _remote;
    if (remote == null) return PricesApplyResult.unavailable;
    final RemotePrices fetched;
    try {
      fetched = await remote.fetch();
    } on PricesUnavailable {
      return PricesApplyResult.unavailable;
    }
    return apply(fetched.block);
  }

  /// Sets a manual price for [symbol] (one [perUnit] in [price]'s currency).
  /// It wins over the backend price until [clearManualOverride]. Throws
  /// [PricesRejected] ([PricesRejected.malformed]) for a symbol or unit that
  /// is not storable or a price that is not above zero.
  Future<void> setManualOverride({
    required String symbol,
    required Money price,
    required String perUnit,
  }) async {
    if (!isValidPriceSymbol(symbol) ||
        !price.isPositive ||
        !RegExp(r'^[a-z0-9_]{1,16}$').hasMatch(perUnit)) {
      throw PricesRejected(PricesRejected.malformed);
    }
    await _dao.upsertQuote((
      symbol: symbol,
      price: price,
      perUnit: perUnit,
      asOf: _nowMs,
    ), source: PriceSource.manual);
  }

  /// Ends the override: the backend price (if any) applies again.
  Future<void> clearManualOverride(String symbol, Currency currency) =>
      _dao.deleteManualQuote(symbol, currency);

  /// The price to use for [symbol] in [currency], or null when there is none
  /// (EC-35: list the asset in its native unit).
  Future<ResolvedPrice?> price(String symbol, Currency currency) async {
    final rows = await _dao.quotes(symbol, currency);
    return resolvePrice(
      [for (final r in rows) _stored(r)],
      nowMs: _nowMs,
      reportedStale: await _reportedStale(),
    );
  }

  /// The ≈ view: [amount] in [to], or [MissingRate] (EC-35).
  Future<ApproxResult> convertApprox(Money amount, Currency to) async =>
      (await fxTable()).convertApprox(amount, to, nowMs: _nowMs);

  Future<FxTable> fxTable() async => FxTable([
    for (final r in await _dao.allRates())
      FxQuote(
        base: Currency.of(r.base),
        quote: Currency.of(r.quote),
        rateE9: r.rateE9,
        asOfMs: r.asOf,
      ),
  ], reportedStale: await _reportedStale());

  Future<PricesStatus> status() async {
    final asOf = await _newestBackendAsOf();
    final manual = await (_db.select(
      _db.priceQuotes,
    )..where((p) => p.source.equals(PriceSource.manual))).get();
    return PricesStatus(
      backendAsOfMs: asOf,
      stale:
          asOf != null &&
          isPriceStale(
            asOfMs: asOf,
            nowMs: _nowMs,
            reportedStale: await _reportedStale(),
          ),
      hasManualOverride: manual.isNotEmpty,
    );
  }

  StoredQuote _stored(PriceQuoteRow r) => StoredQuote(
    symbol: r.symbol,
    price: r.price,
    perUnit: r.perUnit,
    asOfMs: r.asOf,
    origin: r.source == PriceSource.manual
        ? PriceOrigin.manual
        : PriceOrigin.backend,
  );

  Future<bool> _reportedStale() async {
    final bytes = await _secure.read(pricesReportedStaleKey);
    return bytes != null && bytes.length == 1 && bytes[0] == 1;
  }

  /// Newest `as_of` over backend quotes and rates.
  Future<int?> _newestBackendAsOf() async {
    int? newest;
    final quotes = await (_db.select(
      _db.priceQuotes,
    )..where((p) => p.source.equals(PriceSource.backend))).get();
    for (final q in quotes) {
      if (newest == null || q.asOf > newest) newest = q.asOf;
    }
    for (final r in await _dao.allRates()) {
      if (newest == null || r.asOf > newest) newest = r.asOf;
    }
    return newest;
  }
}
