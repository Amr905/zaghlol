// T-342: what the plan executor computed for the online helper (ask-llm.md
// section 3). Typed figures only: every amount is a `Money` with its own
// currency, results are listed per currency (primary first) and nothing
// here sums two currencies. The template filler (T-343) turns these into
// words; the executor never builds text. Types that can hold the user's own
// names have a redacted `toString`.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../insights/domain/chart_models.dart';

/// What a plan filter points at.
enum LlmTargetKind { everything, category, merchant, account }

final class LlmTarget {
  const LlmTarget._(
    this.kind, {
    this.categoryId,
    this.slug,
    this.merchantIds = const {},
    this.accountIds = const {},
    this.label,
  });

  static const everything = LlmTarget._(LlmTargetKind.everything);

  factory LlmTarget.category(String id, {String? slug, String? label}) =>
      LlmTarget._(
        LlmTargetKind.category,
        categoryId: id,
        slug: slug,
        label: label,
      );

  factory LlmTarget.merchants(Set<String> ids, {String? label}) =>
      LlmTarget._(LlmTargetKind.merchant, merchantIds: ids, label: label);

  factory LlmTarget.accounts(Set<String> ids, {String? label}) =>
      LlmTarget._(LlmTargetKind.account, accountIds: ids, label: label);

  final LlmTargetKind kind;
  final String? categoryId;

  /// The closed-catalogue slug when the plan named one.
  final String? slug;
  final Set<String> merchantIds;
  final Set<String> accountIds;

  /// The user's own name for it (in memory only), when one is known.
  final String? label;

  @override
  String toString() => 'LlmTarget(${kind.name}, <redacted>)';
}

sealed class LlmAnswer {
  const LlmAnswer();
}

/// PL-SPEND: one net-spend figure per currency (zero figures left out).
final class LlmDataAnswer extends LlmAnswer {
  const LlmDataAnswer({
    required this.period,
    required this.target,
    required this.figures,
  });
  final ChartPeriod period;
  final LlmTarget target;
  final List<Money> figures;
}

final class LlmCompareFigure {
  const LlmCompareFigure({
    required this.current,
    required this.previous,
    required this.deltaBp,
  });
  final Money current;
  final Money previous;

  /// (current - previous) / previous in basis points; null when previous is
  /// zero. The difference itself is `current - previous`.
  final int? deltaBp;
  Money get difference => current - previous;
}

/// PL-COMPARE: period A against period B, per currency.
final class LlmCompareAnswer extends LlmAnswer {
  const LlmCompareAnswer({
    required this.periodA,
    required this.periodB,
    required this.target,
    required this.figures,
  });
  final ChartPeriod periodA;
  final ChartPeriod periodB;
  final LlmTarget target;
  final List<LlmCompareFigure> figures;
}

final class LlmRankedRow {
  const LlmRankedRow({
    required this.amount,
    this.id,
    this.name,
    this.shareBp,
    this.date,
  });
  final Money amount;

  /// Category id, merchant norm, account id or transaction id.
  final String? id;
  final String? name;
  final int? shareBp;
  final CivilDate? date;

  @override
  String toString() => 'LlmRankedRow(<redacted>)';
}

/// One ranked list in one currency; [other] is the rest, folded together.
final class LlmRankedList {
  const LlmRankedList({required this.rows, this.other});
  final List<LlmRankedRow> rows;
  final Money? other;
  Currency get currency => rows.first.amount.currency;
}

/// PL-BREAKDOWN: spend grouped, one list per currency.
final class LlmBreakdownAnswer extends LlmAnswer {
  const LlmBreakdownAnswer({
    required this.period,
    required this.by,
    required this.lists,
  });
  final ChartPeriod period;
  final BreakdownBy by;
  final List<LlmRankedList> lists;
}

/// PL-TOPN: a ranking, one list per currency.
final class LlmTopNAnswer extends LlmAnswer {
  const LlmTopNAnswer({
    required this.period,
    required this.of,
    required this.lists,
  });
  final ChartPeriod period;
  final TopOf of;
  final List<LlmRankedList> lists;
}

final class LlmAverageFigure {
  const LlmAverageFigure({
    required this.total,
    required this.units,
    required this.average,
  });
  final Money total;

  /// Full units the total was divided by (at least 1).
  final int units;
  final Money average;
}

/// PL-AVERAGE: total over full units only. [range] is what was counted;
/// [partialExcluded] says part of the asked period was left out (an
/// unfinished current unit, days before the first transaction).
final class LlmAverageAnswer extends LlmAnswer {
  const LlmAverageAnswer({
    required this.per,
    required this.period,
    required this.range,
    required this.target,
    required this.figures,
    required this.partialExcluded,
  });
  final AveragePer per;
  final ChartPeriod period;
  final ChartPeriod range;
  final LlmTarget target;
  final List<LlmAverageFigure> figures;
  final bool partialExcluded;
}

/// PL-INCOME: income per currency.
final class LlmIncomeAnswer extends LlmAnswer {
  const LlmIncomeAnswer({required this.period, required this.figures});
  final ChartPeriod period;
  final List<Money> figures;
}

final class LlmSavedFigure {
  const LlmSavedFigure({required this.income, required this.spend});
  final Money income;
  final Money spend;

  /// May be negative ("spent more than came in").
  Money get saved => income - spend;
}

/// PL-SAVED: income minus spend, per currency.
final class LlmSavedAnswer extends LlmAnswer {
  const LlmSavedAnswer({required this.period, required this.figures});
  final ChartPeriod period;
  final List<LlmSavedFigure> figures;
}

final class LlmBillsFigure {
  const LlmBillsFigure({required this.total, required this.dues});
  final Money total;
  final List<InstallmentDue> dues;
}

/// PL-BILLS-DUE: unpaid dues in the window, per currency.
final class LlmBillsAnswer extends LlmAnswer {
  const LlmBillsAnswer({required this.windowEnd, required this.figures});
  final CivilDate windowEnd;
  final List<LlmBillsFigure> figures;
}

final class LlmBudgetFigure {
  const LlmBudgetFigure({
    required this.budget,
    required this.spent,
    required this.remaining,
  });
  final Money budget;
  final Money spent;

  /// May be negative (over budget).
  final Money remaining;
}

/// PL-BUDGET-LEFT: budget minus spend for the current cycle, per currency.
/// No budget at all: [figures] is empty ([hasBudget] false).
final class LlmBudgetLeftAnswer extends LlmAnswer {
  const LlmBudgetLeftAnswer({
    required this.cycle,
    required this.target,
    required this.figures,
  });
  final ChartPeriod cycle;
  final LlmTarget target;
  final List<LlmBudgetFigure> figures;
  bool get hasBudget => figures.isNotEmpty;
}

/// PL-SAFE-SPEND: safe to spend per day, per currency with a budget. With
/// no budget (EC-24) [figures] is empty and the UI shows the hint only.
final class LlmSafeSpendAnswer extends LlmAnswer {
  const LlmSafeSpendAnswer({
    required this.daysRemaining,
    required this.figures,
  });
  final int daysRemaining;
  final List<Money> figures;
  bool get hasBudget => figures.isNotEmpty;
}

final class LlmBalanceFigure {
  const LlmBalanceFigure({
    required this.balance,
    required this.asOf,
    this.accountLabel,
    this.liability = false,
  });
  final Money balance;
  final DateTime asOf;
  final String? accountLabel;
  final bool liability;

  @override
  String toString() => 'LlmBalanceFigure(<redacted>)';
}

/// PL-BALANCE: latest balances; named accounts one by one, never adding a
/// debit and a credit balance.
final class LlmBalanceAnswer extends LlmAnswer {
  const LlmBalanceAnswer({required this.figures});
  final List<LlmBalanceFigure> figures;
}

/// PL-WHATIF-CUT: one outcome per currency of the target's spend. A
/// currency with no outcome in [byCurrency] has fewer than one full period
/// (or a base of zero or less): "not enough data" (EC-23).
final class LlmWhatIfAnswer extends LlmAnswer {
  const LlmWhatIfAnswer({
    required this.target,
    required this.months,
    required this.outcomes,
  });
  final LlmTarget target;
  final int months;
  final List<LlmWhatIfOutcome> outcomes;
}

final class LlmWhatIfOutcome {
  const LlmWhatIfOutcome(this.currency, this.result);
  final Currency currency;

  /// Null: not enough data in this currency.
  final WhatIfCutResult? result;
}

/// PL-WHATIF-SAVE: amount x months, no interest.
final class LlmWhatIfSaveAnswer extends LlmAnswer {
  const LlmWhatIfSaveAnswer({
    required this.amount,
    required this.months,
    required this.total,
  });
  final Money amount;
  final int months;
  final Money total;
}

/// PL-SUGGEST: top suggestions per currency (an empty list: none apply).
final class LlmSuggestAnswer extends LlmAnswer {
  const LlmSuggestAnswer({required this.perCurrency});
  final List<CurrencySuggestions> perCurrency;
}

/// One PL-INVEST base S and what it buys.
final class LlmInvestFigure {
  const LlmInvestFigure({required this.saved, required this.illustration});
  final Money saved;
  final InvestIllustration illustration;
}

/// PL-INVEST: illustrations per currency of S. Wording is app-owned.
final class LlmInvestAnswer extends LlmAnswer {
  const LlmInvestAnswer({
    required this.horizonMonths,
    required this.figures,
    required this.instruments,
  });
  final int horizonMonths;
  final List<LlmInvestFigure> figures;
  final Set<InvestInstrument> instruments;
}

enum LlmChipKind { category, merchant, account }

/// A suggestion the user can tap after a name was not found.
final class LlmChip {
  const LlmChip(this.kind, this.id, this.label);
  final LlmChipKind kind;
  final String id;
  final String label;

  @override
  String toString() => 'LlmChip(${kind.name}, <redacted>)';
}

/// A name the plan used is not in the user's data: ask, never guess.
final class LlmNotFoundAnswer extends LlmAnswer {
  const LlmNotFoundAnswer(this.chips);
  final List<LlmChip> chips;
}

enum LlmFallbackReason {
  unsupported,
  ambiguous,
  zakah,
  noData,

  /// A placeholder of the plan is not in the mask map.
  missingPlaceholder,

  /// A repository read failed or the plan could not be computed.
  failed,
}

/// Polite "can't answer that yet" with example chips; never a number.
final class LlmFallbackAnswer extends LlmAnswer {
  const LlmFallbackAnswer(this.reason);
  final LlmFallbackReason reason;
}

/// PL-REFUSE: app-owned copy per reason.
final class LlmRefuseAnswer extends LlmAnswer {
  const LlmRefuseAnswer(this.reason, {required this.selfHarm});
  final RefuseReason reason;
  final bool selfHarm;
}
