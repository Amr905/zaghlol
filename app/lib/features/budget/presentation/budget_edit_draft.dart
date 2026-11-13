// T-101: S-23 draft and its validation (FR-BUD-02/03, S-23 validation).
// Pure; limits are parsed to integer minor units per the currency exponent.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/money_format.dart';

/// Field keys in the error map of [validateDraft].
const String budgetTotalKey = 'total';
const String budgetFirstKey = 'first';
const String budgetSecondKey = 'second';

const int budgetMinThreshold = 1;
const int budgetMaxThreshold = 150;

enum BudgetEditError {
  limitNegative,
  thresholdRange,
  thresholdOrder,
  limitInvalid,
}

final class BudgetDraft {
  const BudgetDraft({
    required this.currency,
    required this.useTotal,
    required this.totalText,
    required this.categoryTexts,
    required this.first,
    required this.second,
    required this.rollover,
  });

  final Currency currency;

  /// false = overall is the sum of the categories (A-16).
  final bool useTotal;
  final String totalText;

  /// Category id -> typed limit; blank = no budget.
  final Map<String, String> categoryTexts;
  final int? first;
  final int? second;
  final bool rollover;
}

final class BudgetValidated {
  const BudgetValidated({
    required this.total,
    required this.limits,
    required this.thresholds,
  });

  /// Null when the overall is the sum of categories (or blank).
  final Money? total;

  /// Categories with a limit above zero.
  final Map<String, Money> limits;
  final List<int> thresholds;
}

/// Money of a field: null for blank, [BudgetEditError.limitInvalid] for text
/// that doesn't parse, [BudgetEditError.limitNegative] below zero.
(Money?, BudgetEditError?) parseLimit(String text, Currency c) {
  final t = text.trim();
  if (t.isEmpty) return (null, null);
  final m = MoneyFormat.parseInput(t, c);
  if (m == null) {
    return (
      null,
      t.startsWith('-')
          ? BudgetEditError.limitNegative
          : BudgetEditError.limitInvalid,
    );
  }
  if (m.minor < 0) return (null, BudgetEditError.limitNegative);
  return (m, null);
}

/// Errors per field key (`total`, a category id, `first`, `second`); empty
/// when [draft] is valid.
Map<String, BudgetEditError> validateDraft(BudgetDraft d) {
  final out = <String, BudgetEditError>{};
  if (d.useTotal) {
    final e = parseLimit(d.totalText, d.currency).$2;
    if (e != null) out[budgetTotalKey] = e;
  }
  d.categoryTexts.forEach((id, t) {
    final e = parseLimit(t, d.currency).$2;
    if (e != null) out[id] = e;
  });
  final f = d.first;
  final s = d.second;
  if (f == null || f < budgetMinThreshold || f > budgetMaxThreshold) {
    out[budgetFirstKey] = BudgetEditError.thresholdRange;
  }
  if (s == null || s < budgetMinThreshold || s > budgetMaxThreshold) {
    out[budgetSecondKey] = BudgetEditError.thresholdRange;
  }
  if (!out.containsKey(budgetFirstKey) &&
      !out.containsKey(budgetSecondKey) &&
      f! >= s!) {
    out[budgetFirstKey] = BudgetEditError.thresholdOrder;
  }
  return out;
}

BudgetValidated validated(BudgetDraft d) {
  final limits = <String, Money>{};
  d.categoryTexts.forEach((id, t) {
    final m = parseLimit(t, d.currency).$1;
    if (m != null && m.minor > 0) limits[id] = m;
  });
  final total = d.useTotal ? parseLimit(d.totalText, d.currency).$1 : null;
  return BudgetValidated(
    total: total != null && total.minor > 0 ? total : null,
    limits: limits,
    thresholds: [d.first!, d.second!],
  );
}
