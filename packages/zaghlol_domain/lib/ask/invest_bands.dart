/// Investment suggestion bands for the Ask helper (T-327, SRS ask-llm §3.4a,
/// D-93).
///
/// Pure Dart over minor units. The gold comparison is exact: no rounding and
/// no floating point anywhere.
library;

import '../money/currency.dart';
import '../money/money.dart';

/// Which answer the amount S gets.
enum InvestBand {
  /// S <= 0: "nothing saved" answer plus the suggestion chip.
  nothingSaved,

  /// 0 < S <= minimum (EGP): encouraging saving line, no instruments.
  small,

  /// minimum < S < price of the minimum gold weight: "stocks in general"
  /// line (no named product), gold line dropped, USD and certificate kept.
  stocks,

  /// S >= price of the minimum gold weight (or a non-EGP source, which keeps
  /// the plain §3.4 behaviour): gold plus the other illustrations.
  gold,

  /// EGP source above the minimum but no gold price at all: no stocks line,
  /// no gold line; USD and certificate kept.
  goldUnknown,
}

/// Gold price per gram for one karat in one currency, with its date.
final class GoldQuote {
  const GoldQuote({
    required this.karat,
    required this.pricePerGram,
    required this.asOf,
  });

  final int karat;
  final Money pricePerGram;
  final DateTime asOf;
}

/// Remote-config thresholds (`ask.invest_min_egp`, `ask.invest_gold_min_cg`,
/// `ask.invest_gold_karat`). Parameters, never constants in the logic.
final class InvestThresholds {
  const InvestThresholds({
    required this.minEgp,
    this.goldMinCentigrams = 25,
    this.goldKarat = 21,
  });

  /// Defaults: EGP 100.00, 0.25 g, 21K.
  factory InvestThresholds.defaults() =>
      InvestThresholds(minEgp: Money.parse('100.00', Currency.of('EGP')));

  /// Amounts up to and including this get the saving line only (EGP).
  final Money minEgp;

  /// Minimum gold weight in centigrams (25 = 0.25 g).
  final int goldMinCentigrams;

  /// Karat whose price defines the gold threshold G.
  final int goldKarat;
}

BigInt _pow10(int n) => BigInt.from(10).pow(n);

/// Compares `amount` against `centigrams` of gold at [pricePerGram], exactly:
/// returns negative, zero or positive like [Comparable.compareTo].
///
/// amount_major vs (cg / 100) * price_major, cross-multiplied in [BigInt].
int compareToGoldWeight(Money amount, int centigrams, Money pricePerGram) {
  final left =
      BigInt.from(amount.minor) *
      BigInt.from(100) *
      _pow10(pricePerGram.currency.exponent);
  final right =
      BigInt.from(centigrams) *
      BigInt.from(pricePerGram.minor) *
      _pow10(amount.currency.exponent);
  return left.compareTo(right);
}

/// Classifies [saved] (S) per D-93. [goldPrice] is the price of
/// [InvestThresholds.goldKarat] in EGP, or null when none was ever received.
///
/// Non-EGP amounts are never converted for comparison: they only split into
/// [InvestBand.nothingSaved] and [InvestBand.gold] (the §3.4 behaviour, where
/// a missing price becomes a "not included" row).
InvestBand investBand(
  Money saved,
  GoldQuote? goldPrice,
  InvestThresholds thresholds,
) {
  if (saved.minor <= 0) return InvestBand.nothingSaved;
  if (saved.currency.code != 'EGP') return InvestBand.gold;
  if (saved <= thresholds.minEgp) return InvestBand.small;
  final price = goldPrice?.pricePerGram;
  if (price == null ||
      price.currency.code != 'EGP' ||
      price.minor <= 0 ||
      goldPrice!.karat != thresholds.goldKarat) {
    return InvestBand.goldUnknown;
  }
  return compareToGoldWeight(saved, thresholds.goldMinCentigrams, price) >= 0
      ? InvestBand.gold
      : InvestBand.stocks;
}
