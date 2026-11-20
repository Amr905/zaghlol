// T-199: the words for where a breakdown line's figure comes from, with its
// date. Text plus date, never colour alone. No amounts here.

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart';

String balanceSourceText(
  AppLocalizations l,
  BreakdownLine line, {
  required String lang,
  required DigitsMode digits,
}) {
  String date() => line.asOf == null
      ? ''
      : ZDateFormat.date(line.asOf!.toLocal(), lang, digits);
  final base = switch (line.source) {
    BalanceSource.unknown => l.networthSrcUnknown,
    BalanceSource.asset => l.networthSrcAsset,
    BalanceSource.installments => l.networthSrcInstallments,
    BalanceSource.computed => l.networthSrcComputed(date()),
    BalanceSource.userEntered => l.networthSrcUser(date()),
    BalanceSource.reported => switch (line.basis) {
      AnchorBasis.reportedAvailable => l.networthSrcAvailable(date()),
      AnchorBasis.limitMinusAvailable => l.networthSrcLimitMinusAvailable(
        date(),
      ),
      _ =>
        line.isLiability
            ? l.networthSrcReportedOwed(date())
            : l.networthSrcReported(date()),
    },
  };
  return line.stale ? '$base · ${l.networthStale}' : base;
}
