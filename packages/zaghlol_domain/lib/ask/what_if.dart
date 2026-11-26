/// What-if calculators for the Ask helper (T-326, SRS ask-llm §3.2, EC-23).
///
/// Pure functions over already-aggregated inputs. All arithmetic is integer
/// minor units; rounding is half-even and applied once per figure.
library;

import '../money/currency.dart';
import '../money/money.dart';
import '../money/rounding.dart';

/// How many full periods the base B averages over at most.
const int whatIfBasisPeriods = 3;

/// How the user states the cut.
sealed class WhatIfMode {
  const WhatIfMode();
}

/// Cut a share of the base: [percent] in 1..100.
final class WhatIfPercent extends WhatIfMode {
  const WhatIfPercent(this.percent);
  final int percent;
}

/// Cut a fixed monthly [amount] (capped at the base).
final class WhatIfAmount extends WhatIfMode {
  const WhatIfAmount(this.amount);
  final Money amount;
}

sealed class WhatIfCutOutcome {
  const WhatIfCutOutcome();
}

/// Fewer than one full period of data: no figure (EC-23).
final class NotEnoughData extends WhatIfCutOutcome {
  const NotEnoughData();
}

final class WhatIfCutResult extends WhatIfCutOutcome {
  const WhatIfCutResult({
    required this.base,
    required this.monthlySaving,
    required this.total,
    required this.months,
    required this.basisPeriods,
    required this.capped,
  });

  /// Average monthly spend over the basis periods.
  final Money base;
  final Money monthlySaving;
  final Money total;
  final int months;

  /// Number of full periods actually used (1..3).
  final int basisPeriods;

  /// True when an amount-mode cut exceeded the base and was capped to it.
  final bool capped;
}

void _checkMonths(int months) {
  if (months < 1 || months > 60) {
    throw ArgumentError('months must be in 1..60');
  }
}

/// [spendPerFullPeriod] holds the target's spend in one currency per full
/// period, oldest first. Only the last [whatIfBasisPeriods] are used.
WhatIfCutOutcome whatIfCut({
  required List<Money> spendPerFullPeriod,
  required WhatIfMode mode,
  required int months,
}) {
  _checkMonths(months);
  if (mode is WhatIfPercent && (mode.percent < 1 || mode.percent > 100)) {
    throw ArgumentError('percent must be in 1..100');
  }
  if (mode is WhatIfAmount && mode.amount.minor <= 0) {
    throw ArgumentError('amount must be positive');
  }
  if (spendPerFullPeriod.isEmpty) return const NotEnoughData();
  final start = spendPerFullPeriod.length > whatIfBasisPeriods
      ? spendPerFullPeriod.length - whatIfBasisPeriods
      : 0;
  final used = spendPerFullPeriod.sublist(start);
  final currency = used.first.currency;
  var sum = Money.zero(currency);
  for (final p in used) {
    sum = sum + p; // throws CurrencyMismatch if mixed
  }
  final base = sum.mulDiv(1, used.length, MoneyRounding.halfEven);
  // FU-401: a net-negative or zero base (refunds above spend) has nothing to
  // cut: no figure, never a negative saving or a "capped" negative.
  if (base.minor <= 0) return const NotEnoughData();
  var capped = false;
  final Money monthly;
  switch (mode) {
    case WhatIfPercent(:final percent):
      monthly = base.mulDiv(percent, 100, MoneyRounding.halfEven);
    case WhatIfAmount(:final amount):
      if (amount.currency != currency) {
        throw ArgumentError('amount currency differs from the spend currency');
      }
      capped = amount > base;
      monthly = capped ? base : amount;
  }
  return WhatIfCutResult(
    base: base,
    monthlySaving: monthly,
    total: monthly.times(months),
    months: months,
    basisPeriods: used.length,
    capped: capped,
  );
}

/// One result per currency of the target's spend; nothing is summed across
/// currencies. An amount-mode cut applies to its own currency only; other
/// currencies get no entry.
Map<Currency, WhatIfCutOutcome> whatIfCutByCurrency({
  required Map<Currency, List<Money>> spendByCurrency,
  required WhatIfMode mode,
  required int months,
}) {
  final out = <Currency, WhatIfCutOutcome>{};
  for (final entry in spendByCurrency.entries) {
    if (mode is WhatIfAmount && mode.amount.currency != entry.key) continue;
    out[entry.key] = whatIfCut(
      spendPerFullPeriod: entry.value,
      mode: mode,
      months: months,
    );
  }
  return out;
}

/// PL-WHATIF-SAVE: total = amount x months, no interest.
Money whatIfSave({required Money amount, required int months}) {
  _checkMonths(months);
  if (amount.minor <= 0) throw ArgumentError('amount must be positive');
  return amount.times(months);
}
