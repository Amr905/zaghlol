// T-110: the answers of Ask Zaghlol (FR-CHAT-01/03/04/05). Pure Dart.
// Every figure is a `Money` in ONE currency, and an answer holds one figure
// per currency; nothing is ever converted or summed across currencies
// (CLAUDE.md §2.4). An answer is data, never text: the screen (T-111) turns
// it into Egyptian Arabic or English from ARB keys. Nothing here logs, and
// `toString` of every answer is redacted.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../insights/domain/chart_models.dart';

/// What a spend answer is about.
enum AskTarget { everything, category, merchant, card }

sealed class AskAnswer {
  const AskAnswer();

  @override
  String toString() => '$runtimeType(<redacted>)';
}

/// "How much did I spend ...": one figure per currency.
final class AskSpendAnswer extends AskAnswer {
  const AskSpendAnswer({
    required this.period,
    required this.periodDefaulted,
    required this.target,
    required this.figures,
    this.categoryId,
    this.targetLabel,
  });

  final ChartPeriod period;
  final bool periodDefaulted;
  final AskTarget target;

  /// The category id (localized by the screen) when [target] is category.
  final String? categoryId;

  /// The merchant or card name as the user has it, when [target] is
  /// merchant or card.
  final String? targetLabel;

  /// Net spend per currency, sorted by currency code; never empty and never
  /// two of the same currency.
  final List<Money> figures;
}

final class AskCompareFigure {
  const AskCompareFigure({
    required this.current,
    required this.previous,
    required this.deltaBp,
  });
  final Money current;
  final Money previous;

  /// (current - previous) / previous in basis points; null when previous is 0.
  final int? deltaBp;
}

final class AskCompareAnswer extends AskAnswer {
  const AskCompareAnswer({
    required this.current,
    required this.previous,
    required this.figures,
    required this.target,
    this.categoryId,
    this.targetLabel,
  });
  final ChartPeriod current;
  final ChartPeriod previous;
  final AskTarget target;
  final String? categoryId;
  final String? targetLabel;
  final List<AskCompareFigure> figures;
}

final class AskTopMerchantsAnswer extends AskAnswer {
  const AskTopMerchantsAnswer({
    required this.period,
    required this.periodDefaulted,
    required this.byCurrency,
  });
  final ChartPeriod period;
  final bool periodDefaulted;

  /// Per currency (sorted by code), the top merchants, biggest first.
  final List<List<MerchantSpend>> byCurrency;
}

final class AskBalanceFigure {
  const AskBalanceFigure(this.amount, this.asOf);
  final Money amount;

  /// UTC time of the newest message the figure comes from.
  final DateTime asOf;
}

final class AskBalanceAnswer extends AskAnswer {
  const AskBalanceAnswer({
    required this.figures,
    required this.liability,
    this.accountLabel,
  });

  /// Per currency, sorted by code.
  final List<AskBalanceFigure> figures;

  /// Set when exactly one account was named.
  final String? accountLabel;

  /// Every account counted is a card or BNPL balance (a debt or a limit),
  /// so the figure is not money the user holds.
  final bool liability;
}

final class AskBudgetFigure {
  const AskBudgetFigure({
    required this.budget,
    required this.spent,
    required this.remaining,
  });
  final Money budget;
  final Money spent;

  /// `budget - spent`; negative when over budget.
  final Money remaining;
  bool get isOver => remaining.isNegative;
}

final class AskBudgetAnswer extends AskAnswer {
  const AskBudgetAnswer({required this.cycle, required this.figures});
  final ChartPeriod cycle;
  final List<AskBudgetFigure> figures;
}

final class AskDuesFigure {
  const AskDuesFigure({required this.total, required this.dues});
  final Money total;
  final List<InstallmentDue> dues;
}

final class AskDuesAnswer extends AskAnswer {
  const AskDuesAnswer({required this.windowEnd, required this.figures});

  /// Dues up to this date (inclusive) and anything overdue.
  final CivilDate windowEnd;
  final List<AskDuesFigure> figures;
}

final class AskBiggestAnswer extends AskAnswer {
  const AskBiggestAnswer({
    required this.period,
    required this.periodDefaulted,
    required this.figures,
  });
  final ChartPeriod period;
  final bool periodDefaulted;

  /// One expense per currency, sorted by currency code.
  final List<BiggestExpense> figures;
}

final class AskSavingsFigure {
  const AskSavingsFigure({
    required this.income,
    required this.spend,
    required this.isPartial,
  });
  final Money income;
  final Money spend;
  final bool isPartial;

  /// Negative when the user spent more than they earned.
  Money get net => income - spend;
}

final class AskSavingsAnswer extends AskAnswer {
  const AskSavingsAnswer({
    required this.period,
    required this.periodDefaulted,
    required this.figures,
  });
  final ChartPeriod period;
  final bool periodDefaulted;
  final List<AskSavingsFigure> figures;
}

/// Roast fact kinds (FR-CHAT-04). Each maps to a set of ARB templates that
/// joke about the spending only (A-18): never the person, religion, body
/// or family.
enum RoastKind {
  topCategory,
  merchantRegular,
  lateNight,
  weekendHeavy,
  biggestExpense,
  subscriptions,
  calm,
}

final class RoastFact {
  const RoastFact(
    this.kind, {
    this.amount,
    this.count,
    this.shareBp,
    this.categoryId,
    this.name,
  });
  final RoastKind kind;
  final Money? amount;
  final int? count;
  final int? shareBp;
  final String? categoryId;

  /// A merchant name as the user has it.
  final String? name;

  @override
  String toString() => 'RoastFact($kind)';
}

final class AskRoastAnswer extends AskAnswer {
  const AskRoastAnswer({required this.period, required this.fact});
  final ChartPeriod period;
  final RoastFact fact;
}

enum AskNoDataReason {
  /// Nothing matching in the period.
  noTransactions,
  noBudget,
  noAccounts,
  noDues,
  noIncome,
}

/// The question was understood and there is nothing to report.
final class AskNoDataAnswer extends AskAnswer {
  const AskNoDataAnswer(this.intent, this.reason);
  final AskIntent intent;
  final AskNoDataReason reason;
}

/// The question was not understood. Never a number (FR-CHAT-03); the chips
/// are the example questions.
final class AskFallbackAnswer extends AskAnswer {
  const AskFallbackAnswer(this.reason, this.chips);
  final AskUnrecognizedReason reason;
  final List<AskChip> chips;
}

/// Reading the data failed (database error). Carries no detail.
final class AskUnavailableAnswer extends AskAnswer {
  const AskUnavailableAnswer();
}

/// The chips offered when a question is not understood (FR-CHAT-05).
const List<AskChip> askFallbackChips = [
  AskChip.spendThisMonth,
  AskChip.topMerchants,
  AskChip.budgetLeft,
  AskChip.biggestExpense,
  AskChip.balance,
  AskChip.roast,
];

/// The chips offered under an answer of [intent]: its natural follow-ups.
List<AskChip> followUpChips(AskIntent intent) => switch (intent) {
  AskIntent.spend => const [
    AskChip.compareMonths,
    AskChip.topMerchants,
    AskChip.biggestExpense,
  ],
  AskIntent.comparePeriods => const [
    AskChip.spendThisMonth,
    AskChip.topMerchants,
  ],
  AskIntent.topMerchants => const [
    AskChip.biggestExpense,
    AskChip.spendThisMonth,
  ],
  AskIntent.accountBalance => const [AskChip.budgetLeft, AskChip.upcomingDues],
  AskIntent.budgetRemaining => const [
    AskChip.spendThisMonth,
    AskChip.upcomingDues,
  ],
  AskIntent.upcomingDues => const [AskChip.budgetLeft, AskChip.balance],
  AskIntent.biggestExpense => const [AskChip.topMerchants, AskChip.roast],
  AskIntent.savings => const [AskChip.spendThisMonth, AskChip.compareMonths],
  AskIntent.roast => const [AskChip.savings, AskChip.topMerchants],
};
