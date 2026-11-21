// T-107: locale-aware text for the charts (money, percent, category names).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/digits_mode.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/money_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/settings/settings_providers.dart';
import '../../../budget/presentation/budget_providers_ui.dart'
    show categoryRowsProvider;
import '../../domain/chart_summary.dart';

String chartMoney(WidgetRef ref, BuildContext context, Money m) {
  final lang = Localizations.localeOf(context).languageCode;
  return trimZeroFraction(
    MoneyFormat.format(
      m,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
      hidden: ref.watch(hideAmountsProvider),
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

/// The localized name of category [id]; the "Other" label for null or an
/// unknown id.
String chartCategoryName(WidgetRef ref, BuildContext context, String? id) {
  final l = AppLocalizations.of(context);
  final arabic = Localizations.localeOf(context).languageCode == 'ar';
  final rows = ref.watch(categoryRowsProvider).value;
  if (rows != null) {
    for (final c in rows) {
      if (c.id == id) return arabic ? c.nameAr : c.nameEn;
    }
  }
  return l.insightsChartsOtherSlice;
}

/// An axis label for [m]: whole units under 1000, then `1.2K` / `1.2 ألف`
/// (and millions). Hidden amounts return an empty label (shapes stay, no
/// figures).
String chartCompactMoney(WidgetRef ref, BuildContext context, Money m) {
  if (ref.watch(hideAmountsProvider)) return '';
  final l = AppLocalizations.of(context);
  final lang = Localizations.localeOf(context).languageCode;
  final digits = ref.watch(digitsModeProvider(lang));
  final c = compactAmount(m.minor, m.currency.exponent);
  final sep = digits == DigitsMode.arabicIndic ? '\u066B' : '.';
  final sign = c.tenths < 0 ? '-' : '';
  final abs = c.tenths.abs();
  final body = '${abs ~/ 10}${abs % 10 == 0 ? '' : '$sep${abs % 10}'}';
  final n = digits.render('$sign$body');
  return switch (c.unit) {
    CompactUnit.none => n,
    CompactUnit.thousand => l.insightsAxisThousands(n),
    CompactUnit.million => l.insightsAxisMillions(n),
  };
}
