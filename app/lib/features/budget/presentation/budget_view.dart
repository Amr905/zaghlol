// T-101: the S-22 view model. Pure: turns a cycle's per-currency totals and
// the stored budgets into rows. Budgets count spend in their own currency
// only; nothing here adds two currencies (D-28).

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../application/cycle_overview.dart';
import '../domain/budget_progress.dart';

/// The currency offered when nothing else is known (D-28: EGP first).
final Currency defaultBudgetCurrency = Currency.of('EGP');

/// Percent from which a bar turns terracotta (mockup 09).
const int budgetWarnPercent = 85;

final class BudgetRowView {
  const BudgetRowView({
    required this.categoryId,
    required this.nameAr,
    required this.nameEn,
    required this.progress,
  });

  final String categoryId;
  final String nameAr;
  final String nameEn;
  final BudgetProgress progress;
}

final class CurrencyBudgetView {
  const CurrencyBudgetView({
    required this.currency,
    required this.spent,
    required this.limit,
    required this.percent,
    required this.safePerDay,
    required this.rows,
    required this.notBudgeted,
  });

  final Currency currency;

  /// All spend of the cycle in this currency.
  final Money spent;

  /// The cycle budget basis; null when there is no budget (S-22 empty).
  final Money? limit;
  final int? percent;

  /// Null without a budget or for a past cycle.
  final Money? safePerDay;
  final List<BudgetRowView> rows;

  /// Spend in categories without a limit; zero when none.
  final Money notBudgeted;

  bool get hasBudget => limit != null && limit!.minor > 0;
}

final class BudgetScreenData {
  const BudgetScreenData({
    required this.cycle,
    required this.isCurrent,
    required this.daysRemaining,
    required this.calendarMonth,
    required this.currencies,
    required this.hasPrevious,
  });

  final Cycle cycle;
  final bool isCurrent;
  final int daysRemaining;

  /// No payday set (A-43): the cycle is the calendar month.
  final bool calendarMonth;
  final List<CurrencyBudgetView> currencies;
  final bool hasPrevious;
}

/// A stored cycle budget row, category names resolved by the caller.
final class BudgetInput {
  const BudgetInput({
    required this.spec,
    required this.nameAr,
    required this.nameEn,
  });
  final BudgetSpec spec;
  final String nameAr;
  final String nameEn;
}

BudgetScreenData buildBudgetScreenData({
  required Cycle cycle,
  required CivilDate today,
  required Map<Currency, CycleTotals> totals,
  required Map<Currency, Money> basis,
  required List<BudgetInput> budgets,
  required bool calendarMonth,
  required bool hasPrevious,
}) {
  final overview = buildCycleOverview(
    cycle: cycle,
    today: today,
    totals: totals,
    budgets: basis,
  );
  final isCurrent = cycle.contains(today);
  final views = <CurrencyBudgetView>[];
  final codes = overview.byCurrency.keys.toList()
    ..sort((a, b) => a.code.compareTo(b.code));
  for (final c in codes) {
    final o = overview.byCurrency[c]!;
    final rows = <BudgetRowView>[];
    var budgetedSpend = 0;
    for (final b in budgets) {
      final s = b.spec;
      if (s.categoryId == null || s.limit.currency != c || s.annual) continue;
      final p = evaluateBudget(s, totals);
      budgetedSpend += p.spent.minor;
      rows.add(
        BudgetRowView(
          categoryId: s.categoryId!,
          nameAr: b.nameAr,
          nameEn: b.nameEn,
          progress: p,
        ),
      );
    }
    final limit = o.budget;
    final pct = (limit == null || limit.minor <= 0)
        ? null
        : (o.totals.spend.minor * 100) ~/ limit.minor;
    final rest = o.totals.spend.minor - budgetedSpend;
    views.add(
      CurrencyBudgetView(
        currency: c,
        spent: o.totals.spend,
        limit: limit,
        percent: pct,
        safePerDay: isCurrent ? o.safeToSpend : null,
        rows: rows,
        notBudgeted: Money(c, rest > 0 ? rest : 0),
      ),
    );
  }
  return BudgetScreenData(
    cycle: cycle,
    isCurrent: isCurrent,
    daysRemaining: overview.daysRemaining,
    calendarMonth: calendarMonth,
    currencies: views,
    hasPrevious: hasPrevious,
  );
}
