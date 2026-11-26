/// Investment illustrations for the Ask helper (T-327, SRS ask-llm §3.4).
///
/// Closed output: instruments are an enum, rows carry numbers and dates only,
/// never free text. All figures are labelled approximate by the UI; amounts
/// are integer minor units, rounded half-even once per figure.
library;

import '../money/currency.dart';
import '../money/money.dart';
import '../money/rounding.dart';
import 'invest_bands.dart';

/// The only instruments an illustration can name. There is no index row
/// (no licensed feed, OQ-ASK-02).
enum InvestInstrument { gold, usd, certificate }

/// A price is stale after this long (FR-WLT-03); still used, but flagged.
const Duration investStaleAfter = Duration(hours: 24);

/// USD/EGP: [egpPerUsd] is the price of one US dollar in EGP.
final class InvestFxQuote {
  const InvestFxQuote({required this.egpPerUsd, required this.asOf});
  final Money egpPerUsd;
  final DateTime asOf;
}

/// Prices and rates, all inputs (no I/O here).
final class InvestPrices {
  const InvestPrices({
    this.gold = const [],
    this.usdEgp,
    required this.certificateRateBp,
  });

  /// Gold per gram, any karat and currency; the matching one is picked.
  final List<GoldQuote> gold;
  final InvestFxQuote? usdEgp;

  /// `ask.cd_example_rate_bp`, annual rate in basis points.
  final int certificateRateBp;
}

sealed class InvestRow {
  const InvestRow();
  InvestInstrument get instrument;
}

/// Gold weight the amount would buy, in centigrams (2 decimals of a gram).
final class GoldRow extends InvestRow {
  const GoldRow({
    required this.karat,
    required this.centigrams,
    required this.priceAsOf,
    required this.stale,
  });
  final int karat;
  final int centigrams;
  final DateTime priceAsOf;
  final bool stale;
  @override
  InvestInstrument get instrument => InvestInstrument.gold;
}

/// US dollars. [approximate] is true when converted from EGP (shown with ≈);
/// a USD source is shown as is.
final class UsdRow extends InvestRow {
  const UsdRow({
    required this.amount,
    required this.approximate,
    this.rateAsOf,
    this.stale = false,
  });
  final Money amount;
  final bool approximate;
  final DateTime? rateAsOf;
  final bool stale;
  @override
  InvestInstrument get instrument => InvestInstrument.usd;
}

/// Simple-interest payout (EGP only), an example rate, not an offer.
final class CertificateRow extends InvestRow {
  const CertificateRow({
    required this.payout,
    required this.rateBp,
    required this.months,
  });
  final Money payout;
  final int rateBp;
  final int months;
  @override
  InvestInstrument get instrument => InvestInstrument.certificate;
}

/// No price or rate for this currency: a "not included" line, never converted.
final class NoPriceRow extends InvestRow {
  const NoPriceRow(this.instrument, this.currency);
  @override
  final InvestInstrument instrument;
  final Currency currency;
}

final class InvestIllustration {
  const InvestIllustration({
    required this.band,
    required this.stocksInGeneral,
    required this.rows,
  });

  final InvestBand band;

  /// True in the [InvestBand.stocks] band: the app shows its own general,
  /// conditional "stocks in general" line (no product, no price).
  final bool stocksInGeneral;
  final List<InvestRow> rows;
}

bool _stale(DateTime asOf, DateTime now) =>
    now.difference(asOf) > investStaleAfter;

BigInt _pow10(int n) => BigInt.from(10).pow(n);

/// Builds the illustration rows for [saved] (S) at [now].
InvestIllustration illustrate({
  required Money saved,
  required InvestPrices prices,
  required Set<InvestInstrument> instruments,
  required int horizonMonths,
  required DateTime now,
  required InvestThresholds thresholds,
}) {
  if (horizonMonths < 1 || horizonMonths > 24) {
    throw RangeError.range(horizonMonths, 1, 24, 'horizonMonths');
  }
  final code = saved.currency.code;
  final isEgp = code == 'EGP';

  GoldQuote? pick(int karat) {
    for (final q in prices.gold) {
      if (q.karat == karat &&
          q.pricePerGram.currency == saved.currency &&
          q.pricePerGram.minor > 0) {
        return q;
      }
    }
    return null;
  }

  final band = investBand(
    saved,
    isEgp ? pick(thresholds.goldKarat) : null,
    thresholds,
  );
  if (band == InvestBand.nothingSaved || band == InvestBand.small) {
    return InvestIllustration(
      band: band,
      stocksInGeneral: false,
      rows: const [],
    );
  }

  final rows = <InvestRow>[];

  if (instruments.contains(InvestInstrument.gold) && band == InvestBand.gold) {
    var any = false;
    if (code == 'EGP' || code == 'USD') {
      for (final karat in const [21, 24]) {
        final q = pick(karat);
        if (q == null) continue;
        any = true;
        rows.add(
          GoldRow(
            karat: karat,
            centigrams: _centigrams(saved, q.pricePerGram),
            priceAsOf: q.asOf,
            stale: _stale(q.asOf, now),
          ),
        );
      }
    }
    if (!any) rows.add(NoPriceRow(InvestInstrument.gold, saved.currency));
  }

  if (instruments.contains(InvestInstrument.usd)) {
    final fx = prices.usdEgp;
    if (code == 'USD') {
      rows.add(UsdRow(amount: saved, approximate: false));
    } else if (isEgp && fx != null && fx.egpPerUsd.minor > 0) {
      rows.add(
        UsdRow(
          amount: _toUsd(saved, fx.egpPerUsd),
          approximate: true,
          rateAsOf: fx.asOf,
          stale: _stale(fx.asOf, now),
        ),
      );
    } else {
      rows.add(NoPriceRow(InvestInstrument.usd, saved.currency));
    }
  }

  if (instruments.contains(InvestInstrument.certificate) && isEgp) {
    rows.add(
      CertificateRow(
        payout: saved.mulDiv(
          prices.certificateRateBp * horizonMonths,
          10000 * 12,
          MoneyRounding.halfEven,
        ),
        rateBp: prices.certificateRateBp,
        months: horizonMonths,
      ),
    );
  }

  return InvestIllustration(
    band: band,
    stocksInGeneral: band == InvestBand.stocks,
    rows: rows,
  );
}

/// centigrams = S_major / price_major * 100, exact BigInt, half-even once.
int _centigrams(Money saved, Money price) {
  final numerator =
      BigInt.from(saved.minor) *
      _pow10(price.currency.exponent) *
      BigInt.from(100);
  final den = BigInt.from(price.minor) * _pow10(saved.currency.exponent);
  return roundDiv(numerator, den, MoneyRounding.halfEven).toInt();
}

/// USD minor = S_major / rate_major * 10^usdExp, half-even once.
Money _toUsd(Money saved, Money rate) {
  final usd = Currency.of('USD');
  final numerator =
      BigInt.from(saved.minor) *
      _pow10(rate.currency.exponent) *
      _pow10(usd.exponent);
  final den = BigInt.from(rate.minor) * _pow10(saved.currency.exponent);
  return Money(usd, roundDiv(numerator, den, MoneyRounding.halfEven).toInt());
}
