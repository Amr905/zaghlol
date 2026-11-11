// T-112: the pure part of the prices and FX store (FR-WLT-03, BR-FX-01,
// EC-34, EC-35). No Flutter, no Drift.
//
// Units and direction, stated once:
// - A gold price is the price of ONE [GoldQuote.perUnit] (`g` = one gram)
//   of the symbol, as integer minor units of its own currency.
// - An FX rate `base -> quote` with [FxQuote.rateE9] = r means
//   `1 base = r / 1e9 quote`. Rates are exact integers; nothing here is a
//   double.
// - A conversion is only ever the approximate (≈) view: its result type is
//   [Approx], never a plain `Money`, and a missing rate is [MissingRate]
//   (never a guess, never zero).
// - Stale = older than 24 h (strictly), or reported stale by the backend for
//   the last block, or dated in the future beyond a small skew allowance
//   (cannot be verified). A stale value is still returned, but labelled.
// - A manual override wins over the backend price until it is cleared; it
//   is never labelled stale (the user chose it) and is always marked
//   [PriceOrigin.manual].
// Nothing here logs, and errors carry codes only.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// EC-34: data older than this is labelled stale.
const Duration priceStaleAfter = Duration(hours: 24);

/// A phone clock up to this far behind a block's `asOf` is tolerated.
const Duration priceClockSkew = Duration(minutes: 5);

/// Largest rate we store: the `fx_rates.rate_e9` CHECK bound.
final BigInt maxRateE9 = BigInt.from(Money.maxMinor);

final BigInt _e9 = BigInt.from(1000000000);

/// Whether data dated [asOfMs] is stale at [nowMs] (both UTC epoch ms).
/// [reportedStale] is the backend's own `stale` flag for that data.
bool isPriceStale({
  required int asOfMs,
  required int nowMs,
  bool reportedStale = false,
}) {
  if (reportedStale) return true;
  final age = nowMs - asOfMs;
  if (age < -priceClockSkew.inMilliseconds) return true; // unverifiable
  return age > priceStaleAfter.inMilliseconds;
}

/// Codes: [malformed] (the block failed strict parsing), [older] (it is older
/// than what is stored: a replay), [unavailable] (no source, or it failed).
final class PricesRejected extends SafeException {
  PricesRejected(super.code);
  static const String malformed = 'PRICES_MALFORMED';
  static const String older = 'PRICES_OLDER';
  static const String unavailable = 'PRICES_UNAVAILABLE';
}

/// One gold price from the backend: [price] per [perUnit] of [symbol].
final class GoldQuote {
  const GoldQuote({
    required this.symbol,
    required this.price,
    required this.perUnit,
  });
  final String symbol;
  final Money price;
  final String perUnit;
}

/// `1 base = rateE9 / 1e9 quote` (display only, BR-FX-01).
final class FxQuote {
  FxQuote({
    required this.base,
    required this.quote,
    required this.rateE9,
    required this.asOfMs,
  }) : assert(base != quote, 'a rate needs two currencies'),
       assert(rateE9 >= 1 && rateE9 <= Money.maxMinor, 'rate out of range');
  final Currency base;
  final Currency quote;
  final int rateE9;
  final int asOfMs;
}

/// A validated `prices` block of `POST /v1/sync`.
final class PriceBlock {
  const PriceBlock({
    required this.asOfMs,
    required this.reportedStale,
    required this.gold,
    required this.fxBase,
    required this.fxRates,
  });
  final int asOfMs;
  final bool reportedStale;
  final List<GoldQuote> gold;
  final Currency fxBase;

  /// quote currency -> rateE9 for `1 fxBase`.
  final Map<Currency, int> fxRates;
}

final RegExp _symbolPattern = RegExp(r'^[A-Z][A-Z0-9_]{0,15}$');
final RegExp _pricePattern = RegExp(r'^([0-9]{1,12})(?:\.([0-9]{1,6}))?$');
final RegExp _ratePattern = RegExp(r'^([0-9]{1,10})(?:\.([0-9]{1,9}))?$');

/// Most gold rows and FX rates one block may hold (the feed has a handful).
const int maxGoldQuotes = 50;
const int maxFxRates = 200;

/// True for a symbol the store accepts (also for manual overrides).
bool isValidPriceSymbol(String symbol) => _symbolPattern.hasMatch(symbol);

/// The unit a backend symbol is quoted per: `_G` symbols are per gram.
String perUnitOfSymbol(String symbol) => symbol.endsWith('_G') ? 'g' : 'unit';

/// Parses the `prices` block strictly. Any defect rejects the whole block
/// ([PricesRejected.malformed]) so nothing half-valid is stored and no
/// stored data is lost on doubt. A price with more fraction digits than the
/// currency's exponent (other than trailing zeros) is rejected, never
/// rounded.
PriceBlock parsePriceBlock(Object? raw) {
  PricesRejected bad() => PricesRejected(PricesRejected.malformed);
  if (raw is! Map) throw bad();
  final asOfText = raw['asOf'];
  final stale = raw['stale'];
  final gold = raw['gold'];
  final fx = raw['fx'];
  if (asOfText is! String || stale is! bool || gold is! List || fx is! Map) {
    throw bad();
  }
  final asOf = DateTime.tryParse(asOfText);
  if (asOf == null || !asOf.isUtc) throw bad();

  if (gold.isEmpty || gold.length > maxGoldQuotes) throw bad();
  final seen = <String>{};
  final quotes = <GoldQuote>[];
  for (final g in gold) {
    if (g is! Map) throw bad();
    final symbol = g['symbol'];
    final currencyCode = g['currency'];
    final priceText = g['price'];
    if (symbol is! String ||
        currencyCode is! String ||
        priceText is! String ||
        !isValidPriceSymbol(symbol)) {
      throw bad();
    }
    final currency = Currency.tryOf(currencyCode);
    final price = currency == null ? null : _parsePrice(priceText, currency);
    if (price == null || !price.isPositive) throw bad();
    if (!seen.add('$symbol/${currency!.code}')) throw bad();
    quotes.add(
      GoldQuote(symbol: symbol, price: price, perUnit: perUnitOfSymbol(symbol)),
    );
  }

  final baseCode = fx['base'];
  final rates = fx['rates'];
  if (baseCode is! String || rates is! Map) throw bad();
  final base = Currency.tryOf(baseCode);
  if (base == null || rates.isEmpty || rates.length > maxFxRates) throw bad();
  final parsed = <Currency, int>{};
  for (final e in rates.entries) {
    final key = e.key;
    final value = e.value;
    if (key is! String || value is! String) throw bad();
    final quote = Currency.tryOf(key);
    final rate = _parseRateE9(value);
    if (quote == null || quote == base || rate == null) throw bad();
    parsed[quote] = rate;
  }
  return PriceBlock(
    asOfMs: asOf.millisecondsSinceEpoch,
    reportedStale: stale,
    gold: quotes,
    fxBase: base,
    fxRates: parsed,
  );
}

Money? _parsePrice(String text, Currency currency) {
  final m = _pricePattern.firstMatch(text);
  if (m == null) return null;
  var fraction = m.group(2) ?? '';
  while (fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  if (fraction.length > currency.exponent) return null;
  final canonical = fraction.isEmpty ? m.group(1)! : '${m.group(1)}.$fraction';
  return Money.tryParse(canonical, currency);
}

int? _parseRateE9(String text) {
  final m = _ratePattern.firstMatch(text);
  if (m == null) return null;
  final fraction = (m.group(2) ?? '').padRight(9, '0');
  final value = BigInt.parse('${m.group(1)}$fraction');
  if (value < BigInt.one || value > maxRateE9) return null;
  return value.toInt();
}

// ---------------------------------------------------------------- prices --

enum PriceOrigin { backend, manual }

/// A stored quote, as the repository reads it.
final class StoredQuote {
  const StoredQuote({
    required this.symbol,
    required this.price,
    required this.perUnit,
    required this.asOfMs,
    required this.origin,
  });
  final String symbol;
  final Money price;
  final String perUnit;
  final int asOfMs;
  final PriceOrigin origin;
}

/// The price to use, with how much to trust it.
final class ResolvedPrice {
  const ResolvedPrice({
    required this.symbol,
    required this.price,
    required this.perUnit,
    required this.origin,
    required this.asOfMs,
    required this.stale,
  });

  final String symbol;

  /// Price of one [perUnit] in its own currency.
  final Money price;
  final String perUnit;
  final PriceOrigin origin;

  /// Backend: when the feed produced it. Manual: when the user set it.
  final int asOfMs;

  /// True only for a backend price that is stale (never for a manual one).
  final bool stale;

  bool get isManual => origin == PriceOrigin.manual;
}

/// Picks the price for one (symbol, currency) from its stored [quotes]: the
/// manual override if there is one, else the backend price, else null (EC-35:
/// the caller lists the asset in its native unit).
ResolvedPrice? resolvePrice(
  Iterable<StoredQuote> quotes, {
  required int nowMs,
  required bool reportedStale,
}) {
  StoredQuote? manual;
  StoredQuote? backend;
  for (final q in quotes) {
    if (q.origin == PriceOrigin.manual) {
      manual = q;
    } else {
      backend = q;
    }
  }
  final chosen = manual ?? backend;
  if (chosen == null) return null;
  return ResolvedPrice(
    symbol: chosen.symbol,
    price: chosen.price,
    perUnit: chosen.perUnit,
    origin: chosen.origin,
    asOfMs: chosen.asOfMs,
    stale:
        chosen.origin == PriceOrigin.backend &&
        isPriceStale(
          asOfMs: chosen.asOfMs,
          nowMs: nowMs,
          reportedStale: reportedStale,
        ),
  );
}

// ------------------------------------------------------------------- fx ---

sealed class ApproxResult {
  const ApproxResult();
}

/// An approximate (≈) amount. Always shown with the "≈" label, and with a
/// stale label when [stale] (EC-34).
final class Approx extends ApproxResult {
  const Approx({
    required this.amount,
    required this.from,
    required this.stale,
    required this.asOfMs,
    required this.identity,
  });

  /// In the target currency, rounded half-even once.
  final Money amount;
  final Currency from;
  final bool stale;

  /// The oldest rate used; null for an identity conversion.
  final int? asOfMs;

  /// Same currency: exact, not approximate.
  final bool identity;
}

/// No rate path between the two currencies (EC-35). Keep the native amount.
final class MissingRate extends ApproxResult {
  const MissingRate(this.from, this.to);
  final Currency from;
  final Currency to;
}

/// The stored rates, for the ≈ view.
final class FxTable {
  FxTable(Iterable<FxQuote> rates, {required this.reportedStale})
    : _rates = {for (final r in rates) (r.base, r.quote): r};

  final Map<(Currency, Currency), FxQuote> _rates;
  final bool reportedStale;

  bool get isEmpty => _rates.isEmpty;

  /// Converts [amount] to [to] for display only, through a direct rate, the
  /// inverse of a stored rate, or a common base (for example USD). One
  /// rounding step (half-even) on exact integers. Throws [MoneyOverflow] if
  /// the result is out of range.
  ApproxResult convertApprox(Money amount, Currency to, {required int nowMs}) {
    final from = amount.currency;
    if (from == to) {
      return Approx(
        amount: amount,
        from: from,
        stale: false,
        asOfMs: null,
        identity: true,
      );
    }
    // 1 from = num / den to
    BigInt num;
    BigInt den;
    List<FxQuote> legs;
    final direct = _rates[(from, to)];
    final inverse = _rates[(to, from)];
    if (direct != null) {
      num = BigInt.from(direct.rateE9);
      den = _e9;
      legs = [direct];
    } else if (inverse != null) {
      num = _e9;
      den = BigInt.from(inverse.rateE9);
      legs = [inverse];
    } else {
      final bases =
          _rates.keys
              .where((k) => k.$2 == from && _rates.containsKey((k.$1, to)))
              .map((k) => k.$1)
              .toList()
            ..sort((a, b) => a.code.compareTo(b.code));
      if (bases.isEmpty) return MissingRate(from, to);
      final toFrom = _rates[(bases.first, from)]!;
      final toTo = _rates[(bases.first, to)]!;
      // 1 from = (1 / rf) base = (rt / rf) to
      num = BigInt.from(toTo.rateE9);
      den = BigInt.from(toFrom.rateE9);
      legs = [toFrom, toTo];
    }
    final scaleTo = BigInt.from(10).pow(to.exponent);
    final scaleFrom = BigInt.from(10).pow(from.exponent);
    final minor = roundDiv(
      BigInt.from(amount.minor) * num * scaleTo,
      den * scaleFrom,
      MoneyRounding.halfEven,
    );
    if (minor.abs() > BigInt.from(Money.maxMinor)) {
      throw MoneyOverflow(to, MoneyOp.mulDiv);
    }
    var oldest = legs.first.asOfMs;
    var stale = false;
    for (final l in legs) {
      if (l.asOfMs < oldest) oldest = l.asOfMs;
      stale =
          stale ||
          isPriceStale(
            asOfMs: l.asOfMs,
            nowMs: nowMs,
            reportedStale: reportedStale,
          );
    }
    return Approx(
      amount: Money(to, minor.toInt()),
      from: from,
      stale: stale,
      asOfMs: oldest,
      identity: false,
    );
  }
}
