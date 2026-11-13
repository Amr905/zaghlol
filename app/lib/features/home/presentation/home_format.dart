// T-054: small display helpers for Home. Money and dates go through the
// shared formatters (core/l10n); nothing here converts between currencies.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';

/// Locale-bound formatting for one build.
class HomeFormat {
  const HomeFormat(this.languageCode, this.digits);

  factory HomeFormat.of(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    return HomeFormat(lang, ref.watch(digitsModeProvider(lang)));
  }

  final String languageCode;
  final DigitsMode digits;

  String money(Money m) =>
      MoneyFormat.format(m, languageCode: languageCode, digits: digits);

  /// A count as locale digits (for the `{n}` placeholders).
  String count(int n) => digits.render('$n');

  String date(CivilDate d) =>
      ZDateFormat.date(DateTime(d.year, d.month, d.day), languageCode, digits);

  String time(DateTime utc) => ZDateFormat.time(utc, languageCode, digits);

  String dateOf(DateTime utc) => ZDateFormat.date(utc, languageCode, digits);
}
