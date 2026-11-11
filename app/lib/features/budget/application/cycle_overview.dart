// T-051: the Home-facing view of a cycle: totals, budget, safe to spend and
// days left per currency (design note §4-§5). Pure; money stays per currency
// and nothing here adds two currencies.

import 'package:zaghlol_domain/zaghlol_domain.dart';

final class CurrencyOverview {
  const CurrencyOverview({
    required this.currency,
    required this.totals,
    required this.budget,
    required this.safeToSpend,
    required this.underIdealLine,
  });

  final Currency currency;
  final CycleTotals totals;

  /// The cycle budget basis in this currency; null when none.
  final Money? budget;

  /// Per remaining day, minor units, floored; null without a budget (EC-24).
  final Money? safeToSpend;

  /// BR-MAS-02; null without a budget.
  final bool? underIdealLine;
}

final class CycleOverview {
  const CycleOverview({
    required this.cycle,
    required this.today,
    required this.daysRemaining,
    required this.byCurrency,
    required this.incomeTarget,
  });

  final Cycle cycle;
  final CivilDate today;
  final int daysRemaining;
  final Map<Currency, CurrencyOverview> byCurrency;

  /// Passed through for progress UI; not a safe-to-spend input (PO Q4,
  /// provisional — PO to confirm).
  final Money? incomeTarget;
}

/// A currency with a budget and no activity yields zero totals, not a
/// missing key (design note §5).
CycleOverview buildCycleOverview({
  required Cycle cycle,
  required CivilDate today,
  required Map<Currency, CycleTotals> totals,
  required Map<Currency, Money> budgets,
  Money? incomeTarget,
}) {
  final out = <Currency, CurrencyOverview>{};
  for (final c in {...totals.keys, ...budgets.keys}) {
    final t =
        totals[c] ??
        CycleTotals(
          currency: c,
          income: Money.zero(c),
          spend: Money.zero(c),
          pendingSpend: Money.zero(c),
          byCategoryMinor: const {},
        );
    final b = budgets[c];
    final hasBudget = b != null && b.minor != 0;
    out[c] = CurrencyOverview(
      currency: c,
      totals: t,
      budget: b,
      safeToSpend: safeToSpend(
        budget: b,
        spend: t.spend,
        cycle: cycle,
        today: today,
      ),
      underIdealLine: hasBudget
          ? isUnderIdealLine(
              budget: b,
              spend: t.spend,
              cycle: cycle,
              today: today,
            )
          : null,
    );
  }
  return CycleOverview(
    cycle: cycle,
    today: today,
    daysRemaining: cycle.daysRemaining(today),
    byCurrency: out,
    incomeTarget: incomeTarget,
  );
}

/// Milliseconds until the next local midnight, assuming [offsetMin] stays in
/// force (Cairo DST moves the midnight; the caller re-arms after firing and
/// re-evaluates "today"). At least 1000.
int millisUntilNextLocalMidnight(int nowUtcMs, int offsetMin) {
  final today = CivilDate.fromLocalMs(nowUtcMs, offsetMin);
  final next = (today.epochDay + 1) * 86400000 - offsetMin * 60000;
  final d = next - nowUtcMs;
  return d < 1000 ? 1000 : d;
}
