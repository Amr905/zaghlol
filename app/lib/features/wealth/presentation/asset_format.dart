// T-121: display helpers for assets (digits per locale, exact integer maths).

import '../../../core/l10n/digits_mode.dart';

/// `24000` milli -> `24`, `24500` -> `24.5` (Arabic-Indic digits and `٫` in
/// Arabic digit mode).
String formatMilli(int milli, DigitsMode digits) {
  final whole = milli ~/ 1000;
  var frac = (milli % 1000).toString().padLeft(3, '0');
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  final sep = digits == DigitsMode.arabicIndic ? '٫' : '.';
  return digits.render(frac.isEmpty ? '$whole' : '$whole$sep$frac');
}

/// Basis points as a percent: `2700` -> `27%`, `2750` -> `27.5%`.
String formatBp(int bp, DigitsMode digits) {
  final whole = bp ~/ 100;
  var frac = (bp % 100).toString().padLeft(2, '0');
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  final sep = digits == DigitsMode.arabicIndic ? '٫' : '.';
  final pct = digits == DigitsMode.arabicIndic ? '٪' : '%';
  return digits.render(frac.isEmpty ? '$whole' : '$whole$sep$frac') + pct;
}
