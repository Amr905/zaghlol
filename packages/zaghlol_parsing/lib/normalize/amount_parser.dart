import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'currency_markers.dart';
import 'text_normalizer.dart';

/// Which characters mean "thousands" and "decimal" in a numeric token.
///
/// The flag comes from the template, never from guessing: `1.234` is a
/// decimal under [standard] and a thousands group under [eu].
enum NumberLocale {
  /// `,` groups thousands, `.` is the decimal separator (1,234.56).
  standard,

  /// `.` groups thousands, `,` is the decimal separator (1.234,56).
  eu,
}

const Result<Money, ParseFailure> _malformed = Err(
  ParseFailure(ParseFailureReason.malformedAmount),
);
const Result<Money, ParseFailure> _excess = Err(
  ParseFailure(ParseFailureReason.excessPrecision),
);

final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
final RegExp _tokenShape = RegExp(r'^[0-9](?:[0-9.,]*[0-9])?$');
final RegExp _numberRun = RegExp(r'[0-9][0-9.,]*');

/// Parses one numeric token (no currency marker, no sign) into [Money].
///
/// Pure and total: never throws, never rounds, never echoes the input in a
/// failure. Fewer fraction digits than the currency exponent are padded;
/// extra trailing zeros are dropped; any other extra digit gives
/// [ParseFailureReason.excessPrecision]. Everything else that is not a
/// valid number gives [ParseFailureReason.malformedAmount].
Result<Money, ParseFailure> parseAmount(
  String token, {
  required Currency currency,
  NumberLocale locale = NumberLocale.standard,
}) {
  final text = normalizeText(token);
  if (text.length > Money.maxParseLength || !_tokenShape.hasMatch(text)) {
    return _malformed;
  }
  final thousands = locale == NumberLocale.standard ? ',' : '.';
  final decimal = locale == NumberLocale.standard ? '.' : ',';

  final parts = text.split(decimal);
  if (parts.length > 2) {
    return _malformed;
  }
  final wholeRaw = parts[0];
  var fraction = parts.length == 2 ? parts[1] : '';
  if (parts.length == 2 && !_digitsOnly.hasMatch(fraction)) {
    return _malformed;
  }

  final String whole;
  if (wholeRaw.contains(thousands)) {
    final groups = wholeRaw.split(thousands);
    if (!_validGrouping(groups)) {
      return _malformed;
    }
    whole = groups.join();
  } else {
    whole = wholeRaw;
  }
  if (!_digitsOnly.hasMatch(whole)) {
    return _malformed;
  }

  final exponent = currency.exponent;
  while (fraction.length > exponent && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  if (fraction.length > exponent) {
    return _excess;
  }
  final canonical = fraction.isEmpty ? whole : '$whole.$fraction';
  final money = Money.tryParse(canonical, currency);
  return money == null ? _malformed : Result.ok(money);
}

bool _validGrouping(List<String> groups) {
  for (final g in groups) {
    if (!_digitsOnly.hasMatch(g)) {
      return false;
    }
  }
  final first = groups.first.length;
  final rest = groups.sublist(1);
  // Western: 1,234,567
  if (first <= 3 && rest.every((g) => g.length == 3)) {
    return true;
  }
  // Indian: 1,23,456 and 12,34,567 (at least three groups).
  if (groups.length >= 3 &&
      first <= 2 &&
      rest.last.length == 3 &&
      rest.sublist(0, rest.length - 1).every((g) => g.length == 2)) {
    return true;
  }
  return false;
}

/// Finds one number and its currency marker (symbol or ISO code, before or
/// after the number) in [text], then calls [parseAmount].
///
/// With no marker, [fallback] is used; with neither, the result is a
/// failure. Text other than one number and one marker, a second number, or
/// an unknown or conflicting marker is [ParseFailureReason.malformedAmount].
Result<Money, ParseFailure> parseMoneyText(
  String text, {
  Currency? fallback,
  NumberLocale locale = NumberLocale.standard,
}) {
  final normalized = normalizeText(text);
  final matches = _numberRun.allMatches(normalized).toList();
  if (matches.length != 1) {
    return _malformed;
  }
  final match = matches.single;
  final before = normalized.substring(0, match.start).trim();
  final after = normalized.substring(match.end).trim();
  if (before.isNotEmpty && after.isNotEmpty) {
    return _malformed;
  }
  final marker = before.isNotEmpty ? before : after;
  final Currency? currency;
  if (marker.isEmpty) {
    currency = fallback;
  } else {
    currency = resolveCurrencyMarker(marker, fallback);
  }
  if (currency == null) {
    return _malformed;
  }
  return parseAmount(match.group(0)!, currency: currency, locale: locale);
}
