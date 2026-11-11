import 'package:zaghlol_domain/zaghlol_domain.dart';

/// A currency symbol and the ISO codes it can stand for.
///
/// [defaultCode] is used when the caller has no fallback currency; it is
/// null when the symbol is too ambiguous to guess.
final class CurrencyMarker {
  const CurrencyMarker(this.defaultCode, this.candidates);

  final String? defaultCode;
  final List<String> candidates;
}

/// Symbol to currency. Arabic names (`جنيه`, `ج.م`) are template data and
/// do not belong here.
const Map<String, CurrencyMarker> currencySymbols = {
  r'$': CurrencyMarker('USD', [
    'USD',
    'CAD',
    'AUD',
    'NZD',
    'SGD',
    'HKD',
    'MXN',
  ]),
  '£': CurrencyMarker('GBP', ['GBP']),
  '€': CurrencyMarker('EUR', ['EUR']),
  '₹': CurrencyMarker('INR', ['INR']),
  '₺': CurrencyMarker('TRY', ['TRY']),
  '﷼': CurrencyMarker(null, ['SAR', 'QAR', 'OMR', 'YER', 'IRR']),
};

/// Resolves a symbol or a 3-letter ISO code to a [Currency].
///
/// An unambiguous marker always wins over [fallback]. An ambiguous symbol
/// resolves to [fallback] when it is one of its candidates, otherwise to the
/// symbol's default (`$` is USD on an EGP card). A symbol with no default
/// (`﷼`) resolves only through an agreeing fallback. Returns null otherwise.
Currency? resolveCurrencyMarker(String marker, Currency? fallback) {
  final symbol = currencySymbols[marker];
  if (symbol != null) {
    if (symbol.candidates.length == 1) {
      return Currency.tryOf(symbol.candidates.single);
    }
    if (fallback == null) {
      final code = symbol.defaultCode;
      return code == null ? null : Currency.tryOf(code);
    }
    if (symbol.candidates.contains(fallback.code)) {
      return fallback;
    }
    // `$` on an account in another currency (a USD purchase on an EGP card)
    // is USD, like `£` and `€` an explicit marker beats the fallback. A
    // symbol with no default (`﷼`) stays unresolved.
    final code = symbol.defaultCode;
    return code == null ? null : Currency.tryOf(code);
  }
  if (marker.length == 3) {
    return Currency.tryOf(marker.toUpperCase());
  }
  return null;
}
