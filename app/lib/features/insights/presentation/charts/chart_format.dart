// T-107: locale-aware text for the charts (money, percent, category names).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/money_format.dart';

String chartMoney(WidgetRef ref, BuildContext context, Money m) {
  final lang = Localizations.localeOf(context).languageCode;
  return trimZeroFraction(
    MoneyFormat.format(
      m,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
    ),
  );
}

/// Drops an all-zero fraction (`5,400.00` -> `5,400`) from a formatted
/// amount; non-zero fractions stay exact. Display only.
String trimZeroFraction(String formatted) =>
    formatted.replaceAllMapped(RegExp(r'[.٫][0٠]+(?![0-9٠-٩])'), (_) => '');

/// [bp] basis points as a whole percent, e.g. 2750 -> `28%` (half up).
String chartPercentBp(WidgetRef ref, BuildContext context, int bp) =>
    chartPercent(ref, context, (bp + 50) ~/ 100);

String chartPercent(WidgetRef ref, BuildContext context, int p) {
  final lang = Localizations.localeOf(context).languageCode;
  return ref.watch(digitsModeProvider(lang)).render('$p%');
}

/// A money formatter bound to the current locale and digits mode.
String Function(Money) chartMoneyOf(WidgetRef ref, BuildContext context) =>
    (m) => chartMoney(ref, context, m);

/// Strips the currency symbol or code from a formatted amount (a list that
/// already shows the currency once in its header).
String trimCurrency(String formatted) => formatted
    .replaceAll(RegExp(r'\s*ج\.م'), '')
    .replaceAll(RegExp(r'[A-Z]{3}\s*'), '');
