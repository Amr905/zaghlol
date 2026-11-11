// T-019: gold/other price quotes and FX rates (database-schema §2.6,
// FR-WLT-03, BR-FX-01). Rates are display-only: nothing here converts an
// amount. The sync apply replaces the backend quotes and rates inside its
// own transaction (FR-SYNC-03); manual overrides are separate rows
// (`source = 'manual'`) and survive it. Writes go through guardWrite;
// nothing here logs.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `price_quotes.source` values.
abstract final class PriceSource {
  static const String backend = 'backend';
  static const String manual = 'manual';
}

/// One quote to store: [price] per [perUnit] of [symbol].
typedef PriceQuoteInput = ({
  String symbol,
  Money price,
  String perUnit,
  int asOf,
});

/// One FX rate: 1 [base] = [rateE9] / 1e9 [quote].
typedef FxRateInput = ({Currency base, Currency quote, int rateE9, int asOf});

class PricesDao {
  PricesDao(this._db);

  final AppDatabase _db;

  /// Inserts or replaces the quote (symbol, currency, [source]).
  Future<void> upsertQuote(PriceQuoteInput q, {required String source}) {
    final s = q.price.toStorage();
    return guardWrite(
      () => _db
          .into(_db.priceQuotes)
          .insertOnConflictUpdate(
            PriceQuotesCompanion.insert(
              symbol: q.symbol,
              currency: s.currency,
              priceMinor: s.minor,
              perUnit: q.perUnit,
              asOf: q.asOf,
              source: source,
            ),
          ),
    );
  }

  /// Replaces every backend quote with [quotes] in one transaction (manual
  /// quotes are kept). Any refused row rolls the whole set back.
  Future<void> replaceBackendQuotes(List<PriceQuoteInput> quotes) => guardWrite(
    () => _db.transaction(() async {
      await (_db.delete(
        _db.priceQuotes,
      )..where((p) => p.source.equals(PriceSource.backend))).go();
      for (final q in quotes) {
        await upsertQuote(q, source: PriceSource.backend);
      }
    }),
  );

  /// The quotes of [symbol] in [currency]: manual first, then backend.
  Future<List<PriceQuoteRow>> quotes(String symbol, Currency currency) =>
      (_db.select(_db.priceQuotes)
            ..where(
              (p) => p.symbol.equals(symbol) & p.currency.equals(currency.code),
            )
            ..orderBy([(p) => OrderingTerm.desc(p.source)]))
          .get();

  Future<int> deleteManualQuote(String symbol, Currency currency) => guardWrite(
    () =>
        (_db.delete(_db.priceQuotes)..where(
              (p) =>
                  p.symbol.equals(symbol) &
                  p.currency.equals(currency.code) &
                  p.source.equals(PriceSource.manual),
            ))
            .go(),
  );

  /// Inserts or replaces the rate (base, quote).
  Future<void> upsertRate(FxRateInput r) => guardWrite(
    () => _db
        .into(_db.fxRates)
        .insertOnConflictUpdate(
          FxRatesCompanion.insert(
            base: r.base.code,
            quote: r.quote.code,
            rateE9: r.rateE9,
            asOf: r.asOf,
          ),
        ),
  );

  /// Replaces every rate with [rates] in one transaction.
  Future<void> replaceRates(List<FxRateInput> rates) => guardWrite(
    () => _db.transaction(() async {
      await _db.delete(_db.fxRates).go();
      for (final r in rates) {
        await upsertRate(r);
      }
    }),
  );

  Future<FxRateRow?> rate(Currency base, Currency quote) =>
      (_db.select(_db.fxRates)..where(
            (r) => r.base.equals(base.code) & r.quote.equals(quote.code),
          ))
          .getSingleOrNull();

  Future<List<FxRateRow>> allRates() =>
      (_db.select(_db.fxRates)..orderBy([
            (r) => OrderingTerm.asc(r.base),
            (r) => OrderingTerm.asc(r.quote),
          ]))
          .get();
}

class NetworthSnapshotsDao {
  NetworthSnapshotsDao(this._db);

  final AppDatabase _db;

  /// Stores the snapshot of [unit] on [takenOn] (ISO local date), replacing
  /// one taken earlier that day. [unit] is a currency code or a gold symbol;
  /// for a gold unit the values are milligrams.
  Future<void> upsert({
    required String takenOn,
    required String unit,
    required int assetsMinor,
    required int liabilitiesMinor,
  }) => guardWrite(
    () => _db
        .into(_db.networthSnapshots)
        .insertOnConflictUpdate(
          NetworthSnapshotsCompanion.insert(
            takenOn: takenOn,
            unit: unit,
            assetsMinor: assetsMinor,
            liabilitiesMinor: liabilitiesMinor,
          ),
        ),
  );

  /// [upsert] for a currency unit. Both totals must be in one currency,
  /// else [CurrencyMismatch] and nothing is written.
  Future<void> upsertMoney({
    required String takenOn,
    required Money assets,
    required Money liabilities,
  }) async {
    if (assets.currency != liabilities.currency) {
      throw CurrencyMismatch(assets.currency, liabilities.currency);
    }
    await upsert(
      takenOn: takenOn,
      unit: assets.currency.code,
      assetsMinor: assets.toStorage().minor,
      liabilitiesMinor: liabilities.toStorage().minor,
    );
  }

  /// The snapshots of [unit], oldest first (chart 11).
  Future<List<NetworthSnapshotRow>> history(String unit) =>
      (_db.select(_db.networthSnapshots)
            ..where((n) => n.unit.equals(unit))
            ..orderBy([(n) => OrderingTerm.asc(n.takenOn)]))
          .get();

  /// Every unit's snapshot on [takenOn].
  Future<List<NetworthSnapshotRow>> on(String takenOn) =>
      (_db.select(_db.networthSnapshots)
            ..where((n) => n.takenOn.equals(takenOn))
            ..orderBy([(n) => OrderingTerm.asc(n.unit)]))
          .get();
}
