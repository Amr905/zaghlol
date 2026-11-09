// Test-only formatter used by the round-trip property (T-013).
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

enum FormatStyle { asciiWestern, arabicIndic, extended, indian, eu, plain }

/// A formatted amount and the locale flag its parser needs.
typedef Formatted = ({String text, NumberLocale locale});

const Map<String, String> _symbolFor = {
  'USD': r'$',
  'GBP': '£',
  'EUR': '€',
  'INR': '₹',
  'TRY': '₺',
};

String _group(String digits, FormatStyle style) {
  if (style == FormatStyle.plain || digits.length <= 3) {
    return digits;
  }
  final groups = <String>[];
  var rest = digits;
  groups.add(rest.substring(rest.length - 3));
  rest = rest.substring(0, rest.length - 3);
  final size = style == FormatStyle.indian ? 2 : 3;
  while (rest.isNotEmpty) {
    final cut = rest.length > size ? rest.length - size : 0;
    groups.insert(0, rest.substring(cut));
    rest = rest.substring(0, cut);
  }
  return groups.join(',');
}

String _mapDigits(String text, int zero) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit >= 0x30 && unit <= 0x39) {
      out.writeCharCode(zero + unit - 0x30);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Formats [money] in [style]. [markerAfter] puts the marker after the
/// number; [useSymbol] uses a symbol when the currency has an unambiguous one.
Formatted formatMoney(
  Money money,
  FormatStyle style, {
  required bool markerAfter,
  required bool useSymbol,
}) {
  final canonical = money.toCanonicalString();
  final point = canonical.indexOf('.');
  final whole = point < 0 ? canonical : canonical.substring(0, point);
  final fraction = point < 0 ? '' : canonical.substring(point + 1);
  final negative = whole.startsWith('-');
  final digits = negative ? whole.substring(1) : whole;

  var body = _group(digits, style);
  var decimal = '.';
  var locale = NumberLocale.standard;
  switch (style) {
    case FormatStyle.eu:
      body = body.replaceAll(',', '.');
      decimal = ',';
      locale = NumberLocale.eu;
    case FormatStyle.arabicIndic:
      body = body.replaceAll(',', '٬');
      decimal = '٫';
    case FormatStyle.extended:
      body = body.replaceAll(',', '٬');
      decimal = '٫';
    case FormatStyle.asciiWestern:
    case FormatStyle.indian:
    case FormatStyle.plain:
      break;
  }
  var number = fraction.isEmpty ? body : '$body$decimal$fraction';
  if (style == FormatStyle.arabicIndic) {
    number = _mapDigits(number, 0x0660);
  } else if (style == FormatStyle.extended) {
    number = _mapDigits(number, 0x06F0);
  }
  final symbol = _symbolFor[money.currency.code];
  final marker = useSymbol && symbol != null ? symbol : money.currency.code;
  final text = markerAfter ? '$number $marker' : '$marker $number';
  return (text: text, locale: locale);
}
