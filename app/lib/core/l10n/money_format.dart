// T-023 / ADR-017: exact money display. Works on the integer minor units and
// the canonical string only (never a double), so every currency exponent is
// honoured and nothing is rounded.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'digits_mode.dart';

/// The fixed-length mask for a hidden amount (D-67): the length says nothing
/// about the size.
const String kAmountMask = '****';

final RegExp _amountNumber = RegExp(r'[0-9٠-٩]+(?:[,.٬٫][0-9٠-٩]+)*');

/// [text] with every number (either digit script, with its separators)
/// replaced by [kAmountMask]; sign, currency and bidi marks stay. For text that
/// was formatted elsewhere and must not show digits.
String maskAmountText(String text) =>
    text.replaceAll(_amountNumber, kAmountMask);

abstract final class MoneyFormat {
  static final _fsi = String.fromCharCode(0x2068);
  static final _pdi = String.fromCharCode(0x2069);

  /// Arabic symbols we have copy for; every other currency shows its ISO code.
  static const _arSymbols = {'EGP': 'ج.م'};

  /// `1,234.50 EGP` / `١٬٢٣٤٫٥٠ ج.م`, the whole run bidi-isolated so a
  /// negative sign and the currency never reorder in RTL text.
  /// [withCurrency] false gives the number only (still isolated).
  ///
  /// [hidden] (D-67) swaps the digits for [kAmountMask], keeping the sign and
  /// the currency. It is required so a new call site must decide.
  static String format(
    Money money, {
    required String languageCode,
    required DigitsMode digits,
    required bool hidden,
    bool withCurrency = true,
    bool dropZeroFraction = false,
  }) {
    final arabic = languageCode == 'ar';
    final canonical = money.toCanonicalString();
    final negative = canonical.startsWith('-');
    final unsigned = negative ? canonical.substring(1) : canonical;
    final point = unsigned.indexOf('.');
    final whole = point < 0 ? unsigned : unsigned.substring(0, point);
    var fraction = point < 0 ? '' : unsigned.substring(point + 1);
    if (dropZeroFraction && RegExp(r'^0*$').hasMatch(fraction)) fraction = '';

    if (hidden) {
      final sign = negative ? '-' : '';
      final code = money.currency.code;
      final String shown;
      if (!withCurrency) {
        shown = '$sign$kAmountMask';
      } else if (arabic) {
        shown = '$sign$kAmountMask ${_arSymbols[code] ?? code}';
      } else {
        shown = '$code $sign$kAmountMask';
      }
      return '$_fsi$shown$_pdi';
    }

    final groupSep = digits == DigitsMode.arabicIndic ? '٬' : ',';
    final decimalSep = digits == DigitsMode.arabicIndic ? '٫' : '.';
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) {
        grouped.write(groupSep);
      }
      grouped.write(whole[i]);
    }
    final number = StringBuffer(digits.render(grouped.toString()));
    // render() only touches ASCII digits, so the separators are untouched.
    if (fraction.isNotEmpty) {
      number
        ..write(decimalSep)
        ..write(digits.render(fraction));
    }

    final sign = negative ? '-' : '';
    final code = money.currency.code;
    final String text;
    if (!withCurrency) {
      text = '$sign$number';
    } else if (arabic) {
      text = '$sign$number ${_arSymbols[code] ?? code}';
    } else {
      text = '$code $sign$number';
    }
    return '$_fsi$text$_pdi';
  }

  /// The currency as shown next to amounts: `ج.م` in Arabic for EGP, else the
  /// ISO code.
  static String currencyLabel(
    Currency currency, {
    required String languageCode,
  }) => languageCode == 'ar'
      ? (_arSymbols[currency.code] ?? currency.code)
      : currency.code;

  /// Parses typed text (any digit script) into [Money]; null when invalid or
  /// when it has more decimals than [currency] allows.
  static Money? parseInput(String input, Currency currency) =>
      Money.tryParse(normalizeDigits(input), currency);
}
