// T-093: formatting and parsing shared by S-15 / S-16. Amounts are exact
// integer minor units in the transaction's own currency; the implied rate
// is computed with integers (no double) and is only ever a display hint.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/money_format.dart';
import '../../transactions/application/reimbursements.dart';
import '../../transactions/application/transfer_pairing.dart';

final class TransfersFmt {
  const TransfersFmt(this.lang, this.digits);
  final String lang;
  final DigitsMode digits;

  String money(Money m) =>
      MoneyFormat.format(m, languageCode: lang, digits: digits);
  String date(DateTime d) => ZDateFormat.date(d, lang, digits);
  String count(int n) => digits.render('$n');

  /// Text for an amount field: canonical digits in the user's script.
  String input(Money m) => digits.render(m.toCanonicalString());

  /// Exact parse of typed text (any digit script); null when empty,
  /// invalid, over-precise for the currency, or not positive.
  Money? parsePositive(String text, Currency c) {
    final m = MoneyFormat.parseInput(text.trim(), c);
    return m == null || m.minor <= 0 ? null : m;
  }
}

/// "2 min later" / "1 day earlier" for a signed gap in minutes.
String gapLabel(AppLocalizations l, TransfersFmt f, int gapMinutes) {
  final after = gapMinutes >= 0;
  final abs = gapMinutes.abs();
  if (abs < 60) {
    return after
        ? l.transfersLinkAfterMinutes(abs, f.count(abs))
        : l.transfersLinkBeforeMinutes(abs, f.count(abs));
  }
  if (abs < 24 * 60) {
    final h = abs ~/ 60;
    return after
        ? l.transfersLinkAfterHours(h, f.count(h))
        : l.transfersLinkBeforeHours(h, f.count(h));
  }
  final d = abs ~/ (24 * 60);
  return after
      ? l.transfersLinkAfterDays(d, f.count(d))
      : l.transfersLinkBeforeDays(d, f.count(d));
}

/// Implied rate between two different-currency amounts, as the larger
/// currency per one unit of the smaller one (A-61): `49.9 EGP` per `USD`.
/// Null when a side is zero or the currencies are equal.
({Money rate, Currency per})? impliedRate(Money a, Money b) {
  if (a.currency == b.currency || a.minor <= 0 || b.minor <= 0) return null;
  final ea = a.currency.exponent;
  final eb = b.currency.exponent;
  final pa = _pow10(ea);
  final pb = _pow10(eb);
  // Compare majors without division: a/pa vs b/pb.
  final aBigger = BigInt.from(a.minor) * pb >= BigInt.from(b.minor) * pa;
  final big = aBigger ? a : b;
  final small = aBigger ? b : a;
  // rate in big's minor units = bigMinor * 10^eSmall / smallMinor, rounded.
  final num = BigInt.from(big.minor) * _pow10(small.currency.exponent);
  final den = BigInt.from(small.minor);
  final q = (num * BigInt.two + den) ~/ (den * BigInt.two);
  return (rate: Money(big.currency, q.toInt()), per: small.currency);
}

BigInt _pow10(int n) => BigInt.from(10).pow(n);

/// The message for a failure from the use cases; codes only.
String errorMessage(AppLocalizations l, Object error) {
  if (error is ReimbursementException) {
    return switch (error.code) {
      ReimbursementException.sharesExceed => l.transfersSplitErrorSharesExceed,
      ReimbursementException.invalid => l.transfersSplitErrorShareZero,
      _ => l.commonErrorSaveFailed,
    };
  }
  if (error is TransferPairingException) {
    return switch (error.code) {
      TransferPairingException.invalid => l.transfersLinkErrorDirection,
      _ => l.commonErrorSaveFailed,
    };
  }
  return l.commonErrorSaveFailed;
}
