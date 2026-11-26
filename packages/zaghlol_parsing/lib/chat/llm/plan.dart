/// Typed `ask-plan/1` plans (T-331, ask-llm.md section 2). Built only by
/// [PlanValidator] from a reply that passed steps 1 to 5, so the closed
/// catalogue is a sealed hierarchy: anything else never becomes a [Plan].
///
/// Amounts stay decimal strings until [planAmountToMinor] converts them with
/// the currency exponent. No `double` anywhere.
library;

import 'plan_schema.g.dart';

enum PeriodKind {
  day,
  week,
  month,
  year,
  cycle,
  lastDays,
  monthOfYear,
  allTime,
}

enum BreakdownBy { category, merchant, account }

enum TopOf { merchant, category, expense }

enum AveragePer { day, week, month }

enum WhatIfKind { percent, amount }

enum InvestSourceKind { savedLastPeriod, whatIf, amount }

enum Instrument {
  gold('gold'),
  usd('usd'),
  certificate('certificate'),

  /// Wire name `index` (an enum member cannot be called `index`).
  indexFund('index');

  const Instrument(this.wire);
  final String wire;

  static Instrument fromWire(String s) => values.firstWhere((i) => i.wire == s);
}

enum FallbackReason { unsupported, ambiguous, zakah, noData }

enum RefuseReason { offTopic, unsafe, specificPick }

final class PlanPeriod {
  const PlanPeriod({
    required this.kind,
    required this.offset,
    this.lastDays,
    this.month,
    this.year,
  });

  final PeriodKind kind;

  /// -36..0
  final int offset;
  final int? lastDays;
  final int? month;
  final int? year;
}

/// At most one of [slug], [ref], [mention] is set. Holds the user's words, so
/// `toString` is redacted.
final class PlanFilter {
  const PlanFilter({this.slug, this.ref, this.mention, this.currency});

  static const none = PlanFilter();

  final String? slug;
  final String? ref;
  final String? mention;
  final String? currency;

  @override
  String toString() => 'PlanFilter(<redacted>)';
}

final class PlanAmount {
  const PlanAmount(this.amount, this.currency);

  /// ASCII decimal string, e.g. `500` or `12.5`.
  final String amount;

  /// ISO 4217, or null for the primary currency.
  final String? currency;
}

final class PlanMode {
  const PlanMode({
    required this.kind,
    this.percent,
    this.amount,
    this.currency,
  });

  final WhatIfKind kind;
  final int? percent;
  final String? amount;
  final String? currency;
}

sealed class Plan {
  const Plan();

  /// The catalogue name, e.g. `PL-SPEND`.
  String get name;
}

final class PlanSpend extends Plan {
  const PlanSpend(this.period, this.filter);
  final PlanPeriod period;
  final PlanFilter filter;
  @override
  String get name => 'PL-SPEND';
}

final class PlanCompare extends Plan {
  const PlanCompare(this.periodA, this.periodB, this.filter);
  final PlanPeriod periodA;
  final PlanPeriod periodB;
  final PlanFilter filter;
  @override
  String get name => 'PL-COMPARE';
}

final class PlanBreakdown extends Plan {
  const PlanBreakdown(this.period, this.by, this.limit);
  final PlanPeriod period;
  final BreakdownBy by;
  final int limit;
  @override
  String get name => 'PL-BREAKDOWN';
}

final class PlanTopN extends Plan {
  const PlanTopN(this.period, this.of, this.n);
  final PlanPeriod period;
  final TopOf of;
  final int n;
  @override
  String get name => 'PL-TOPN';
}

final class PlanAverage extends Plan {
  const PlanAverage(this.per, this.period, this.filter);
  final AveragePer per;
  final PlanPeriod period;
  final PlanFilter filter;
  @override
  String get name => 'PL-AVERAGE';
}

final class PlanIncome extends Plan {
  const PlanIncome(this.period, this.filter);
  final PlanPeriod period;
  final PlanFilter filter;
  @override
  String get name => 'PL-INCOME';
}

final class PlanSaved extends Plan {
  const PlanSaved(this.period);
  final PlanPeriod period;
  @override
  String get name => 'PL-SAVED';
}

final class PlanBillsDue extends Plan {
  const PlanBillsDue(this.windowDays);
  final int windowDays;
  @override
  String get name => 'PL-BILLS-DUE';
}

final class PlanBudgetLeft extends Plan {
  const PlanBudgetLeft(this.slug);
  final String? slug;
  @override
  String get name => 'PL-BUDGET-LEFT';
}

final class PlanSafeSpend extends Plan {
  const PlanSafeSpend();
  @override
  String get name => 'PL-SAFE-SPEND';
}

final class PlanBalance extends Plan {
  const PlanBalance(this.ref);

  /// An ACCOUNT, CARD or BANK placeholder, or null.
  final String? ref;
  @override
  String get name => 'PL-BALANCE';
  @override
  String toString() => 'PlanBalance(<redacted>)';
}

final class PlanWhatIfCut extends Plan {
  const PlanWhatIfCut(this.target, this.mode, this.months);
  final PlanFilter target;
  final PlanMode mode;
  final int months;
  @override
  String get name => 'PL-WHATIF-CUT';
}

final class PlanWhatIfSave extends Plan {
  const PlanWhatIfSave(this.amount, this.months);
  final PlanAmount amount;
  final int months;
  @override
  String get name => 'PL-WHATIF-SAVE';
}

final class PlanSuggest extends Plan {
  const PlanSuggest(this.currency);
  final String? currency;
  @override
  String get name => 'PL-SUGGEST';
}

final class PlanInvestSource {
  const PlanInvestSource(this.kind, {this.whatIf, this.amount});
  final InvestSourceKind kind;
  final PlanWhatIfCut? whatIf;
  final PlanAmount? amount;
}

final class PlanInvest extends Plan {
  const PlanInvest(this.source, this.instruments, this.horizonMonths);
  final PlanInvestSource source;
  final List<Instrument> instruments;
  final int horizonMonths;
  @override
  String get name => 'PL-INVEST';
}

final class PlanFallback extends Plan {
  const PlanFallback(this.reason);
  final FallbackReason reason;
  @override
  String get name => 'PL-FALLBACK';
}

final class PlanRefuse extends Plan {
  const PlanRefuse(this.reason, {required this.selfHarm});
  final RefuseReason reason;
  final bool selfHarm;
  @override
  String get name => 'PL-REFUSE';
}

/// Minor-unit digits of an ISO 4217 code, as the shared vectors define them
/// (3 for KWD/BHD/OMR/JOD/TND/LYD/IQD, 0 for JPY/KRW, otherwise 2).
int planCurrencyExponent(String currency) =>
    planThreeDecimalCurrencies.contains(currency)
    ? 3
    : planZeroDecimalCurrencies.contains(currency)
    ? 0
    : 2;

/// Converts a plan amount string to integer minor units with [exponent]
/// digits. Returns null when the string has more fraction digits than
/// [exponent] or is not `digits[.digits]`. No `double`.
int? planAmountToMinor(String amount, int exponent) {
  final m = RegExp(r'^([0-9]{1,9})(?:\.([0-9]{1,3}))?$').firstMatch(amount);
  if (m == null) return null;
  final frac = m.group(2) ?? '';
  if (frac.length > exponent) return null;
  return int.parse(m.group(1)! + frac.padRight(exponent, '0'));
}
