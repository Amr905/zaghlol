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

/// How many days of "days to payday" lines one snapshot carries.
const widgetMaxRollDays = 62;

/// The longest line two the native widgets keep (`WidgetView.MAX_TEXT_CHARS`
/// in `WidgetSnapshotStore.kt`, 120 UTF-16 units; they truncate beyond it).
/// Mirror both if either changes (FU-387).
const widgetMaxLineChars = 120;

/// FU-393: a conservative visual budget (UTF-16 units) for line two on the
/// smallest (2x1) widget, which ellipsizes a ~35-unit line («٧ أيام على القبض
/// · + USD, EUR +١»). A line with the hint over this loses the hint and keeps
/// the payday text. One snapshot serves every size, so the rule is global.
/// The on-device check of the 2x1 size (ar/en) is still owed.
const widgetSmallLineBudget = 32;

/// T-284 (D-86): the most ISO codes the hint names before "+N".
const widgetMaxHintCodes = 2;

/// The hint line for other currencies that have a Home card: "+ USD",
/// "+ USD, EUR", "+ USD, EUR +1". Codes only, never an amount or a sum.
/// Wrapped in left-to-right isolates so it reads the same in RTL. Empty when
/// there are none.
String widgetCurrencyHint(List<String> codes, DigitsMode digits) {
  if (codes.isEmpty) return '';
  final shown = codes.take(widgetMaxHintCodes).join(', ');
  final more = codes.length - widgetMaxHintCodes;
  final tail = more > 0 ? ' +${digits.render('$more')}' : '';
  return '\u2066+ $shown$tail\u2069';
}

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
    this.otherCurrencies = const [],
    this.lineBudget = widgetSmallLineBudget,
  });

  /// T-284: ISO codes of the non-primary currencies that have a Home card
  /// (T-278 rule), in card order. Codes only; left out while locked.
  final List<String> otherCurrencies;

  /// Longest line two kept with the hint (FU-393); tests widen it.
  final int lineBudget;

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
  // The codes alone stay visible when amounts are hidden (no amount in
  // them); a locked app shows none, since which currencies are held is
  // financial information.
  final hint = i.appLocked
      ? ''
      : widgetCurrencyHint(i.otherCurrencies, i.digits);
  final safe = overview.byCurrency[i.primaryCurrency]?.safeToSpend;
  if (safe == null) {
    // EC-24: no budget in the primary currency.
    return WidgetSnapshot(
      state: WidgetDisplayState.noBudget,
      primaryText: i.copy.setBudget,
      secondaryText: hint,
      currency: code,
      updatedAtMs: i.nowMs,
    );
  }
  final masked = i.hideAmounts || i.appLocked;
  // The formatter masks too, so the real figure is never built while masked;
  // the widget shows its contract mask (platform-channels.md).
  final formatted = MoneyFormat.format(
    safe,
    languageCode: i.languageCode,
    digits: i.digits,
    hidden: masked,
  );
  final amount = masked ? widgetAmountMask : formatted;
  final days = overview.daysRemaining;
  String line(int n) {
    final text = i.copy.daysToPayday(n, i.digits.render('$n'));
    if (hint.isEmpty) return text;
    final withHint = '$text \u00b7 $hint';
    // FU-387: when it would be cut, the hint goes, never the payday text.
    final budget = i.lineBudget < widgetMaxLineChars
        ? i.lineBudget
        : widgetMaxLineChars;
    return withHint.length > budget ? text : withHint;
  }

  // FU-206b: one finished line per coming day so the widget rolls the count
  // at local midnight by itself (no amount in any of them).
  final perDay = <String>[
    for (var n = days; n >= 1 && days - n < widgetMaxRollDays; n--) line(n),
  ];
  return WidgetSnapshot(
    state: WidgetDisplayState.ok,
    primaryText: i.copy.perDay(amount),
    secondaryText: line(days),
    secondaryTextByDay: perDay,
    daysToPayday: days,
    currency: code,
    updatedAtMs: i.nowMs,
  );
}
