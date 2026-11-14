// T-118 (FR-WID-01): builds the redacted widget snapshot. Pure: the strings
// are formatted here, in the app's language and digits, because the platform
// channel stores only formatted, redaction-aware text (platform-channels.md
// section 5). Nothing here adds two currencies; the widget shows the primary
// currency only. When amounts are hidden, or the app is locked (UX-A-05), the
// amount never enters the snapshot: only the mask does.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/platform/widget_bridge_api.g.dart';
import '../../budget/application/cycle_overview.dart';

/// The mask for a hidden amount (platform-channels.md: `"•••"`).
const widgetAmountMask = '•••';

/// Localized copy, supplied by the composition root from the ARB strings
/// (no copy lives in this file). Each function returns the finished text.
class WidgetCopy {
  const WidgetCopy({
    required this.perDay,
    required this.daysToPayday,
    required this.setBudget,
    required this.openApp,
  });

  /// `commonUnitPerDay`: "{amount}/day".
  final String Function(String amount) perDay;

  /// `homeHeroDaysToPayday(count, n)`: [count] is the number, [formatted]
  /// the same number in the user's digits.
  final String Function(int count, String formatted) daysToPayday;

  /// `homeHeroSetBudget`.
  final String setBudget;

  /// Widget "no data" line (copy-deck key requested from T-087).
  final String openApp;
}

/// The inputs of one snapshot.
class WidgetSnapshotInput {
  const WidgetSnapshotInput({
    required this.overview,
    required this.primaryCurrency,
    required this.hideAmounts,
    required this.appLocked,
    required this.languageCode,
    required this.digits,
    required this.copy,
    required this.nowMs,
  });

  /// Null while there is no data (no cycle read yet).
  final CycleOverview? overview;
  final Currency primaryCurrency;

  /// `hide_amounts.widget`.
  final bool hideAmounts;

  /// App lock enabled and currently locked: amounts are always masked.
  final bool appLocked;
  final String languageCode;
  final DigitsMode digits;
  final WidgetCopy copy;
  final int nowMs;
}

WidgetSnapshot buildWidgetSnapshot(WidgetSnapshotInput i) {
  final code = i.primaryCurrency.code;
  final overview = i.overview;
  if (overview == null) {
    return WidgetSnapshot(
      state: WidgetDisplayState.noData,
      primaryText: i.copy.openApp,
      secondaryText: '',
      currency: code,
      updatedAtMs: i.nowMs,
    );
  }
  final safe = overview.byCurrency[i.primaryCurrency]?.safeToSpend;
  if (safe == null) {
    // EC-24: no budget in the primary currency.
    return WidgetSnapshot(
      state: WidgetDisplayState.noBudget,
      primaryText: i.copy.setBudget,
      secondaryText: '',
      currency: code,
      updatedAtMs: i.nowMs,
    );
  }
  final masked = i.hideAmounts || i.appLocked;
  final amount = masked
      ? widgetAmountMask
      : MoneyFormat.format(
          safe,
          languageCode: i.languageCode,
          digits: i.digits,
        );
  final days = overview.daysRemaining;
  return WidgetSnapshot(
    state: WidgetDisplayState.ok,
    primaryText: i.copy.perDay(amount),
    secondaryText: i.copy.daysToPayday(days, i.digits.render('$days')),
    daysToPayday: days,
    currency: code,
    updatedAtMs: i.nowMs,
  );
}
