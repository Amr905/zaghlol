// T-209 (CHARTS-V2): small text helpers of the v2 tabs.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/money_format.dart';
import '../../../../core/settings/settings_providers.dart';
import '../charts/chart_format.dart';

final String _fsi = String.fromCharCode(0x2068);
final String _pdi = String.fromCharCode(0x2069);

/// [s] wrapped so a Latin or numeric run does not reorder inside RTL text.
String isolate(String s) => '$_fsi$s$_pdi';

/// A whole number in the user's digits.
String v2Digits(WidgetRef ref, BuildContext context, int n) => ref
    .watch(digitsModeProvider(Localizations.localeOf(context).languageCode))
    .render('$n');

/// An axis or bar label for [minor] of [currency]: compact, or the mask when
/// amounts are hidden (D-67).
String v2AxisMoney(
  WidgetRef ref,
  BuildContext context,
  int minor,
  Currency currency,
) => ref.watch(hideAmountsProvider)
    ? kAmountMask
    : chartCompactMoney(ref, context, Money(currency, minor));
