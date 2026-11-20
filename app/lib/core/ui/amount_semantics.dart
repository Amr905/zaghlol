// D-67: a screen reader says "amount hidden", never the `****` glyphs.

import '../l10n/generated/app_localizations.dart';
import '../l10n/money_format.dart';

final String _fsi = String.fromCharCode(0x2068);
final String _pdi = String.fromCharCode(0x2069);

final RegExp _maskedAmount = RegExp(
  '$_fsi?(?:[A-Z]{3} )?[-+]?${RegExp.escape(kAmountMask)}'
  '(?: (?:ج\\.م|[A-Z]{3}|g|جرام))?$_pdi?',
);

/// [label] with every masked amount (sign, currency or unit included)
/// replaced by the localized "amount hidden". Labels without a mask come back
/// unchanged, so it is safe to wrap any composite label that embeds amounts.
String a11yAmounts(AppLocalizations l, String label) =>
    label.contains(kAmountMask)
    ? label.replaceAll(_maskedAmount, l.commonAmountHidden)
    : label;
