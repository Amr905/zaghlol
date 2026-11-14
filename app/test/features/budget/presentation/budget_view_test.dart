// T-101: the S-22 view model. Per-currency only; synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/budget/domain/budget_progress.dart';
import 'package:zaghlol/features/budget/presentation/budget_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'budget_test_support.dart';

CycleTotals totals(Currency c, int spend, Map<String, int> byCat) =>
    CycleTotals(
      currency: c,
      income: Money.zero(c),
      spend: Money(c, spend),
      pendingSpend: Money.zero(c),
      byCategoryMinor: byCat,
    );

BudgetInput input(String id, Currency c, int limitMajor) => BudgetInput(
  spec: BudgetSpec(
    id: 'b-$id',
    categoryId: id,
    limit: Money(c, limitMajor * 100),
    thresholds: const [80, 100],
  ),
  nameAr: id,
  nameEn: id,
);

void main() {
  final cycle = Cycle(
    start: CivilDate(2026, 10, 25),
    end: CivilDate(2026, 11, 24),
  );
  final today = CivilDate(2026, 11, 17);

  test('budgets count only their own currency and never mix', () {
    final d = buildBudgetScreenData(
      cycle: cycle,
      today: today,
      totals: {
        egp: totals(egp, 600000, {'food': 400000, 'fun': 100000}),
        usd: totals(usd, 5000, {'food': 5000}),
      },
      basis: {egp: egpM(10000)},
      budgets: [input('food', egp, 5000)],
      calendarMonth: false,
      hasPrevious: true,
    );
    final e = d.currencies.firstWhere((v) => v.currency == egp);
    final u = d.currencies.firstWhere((v) => v.currency == usd);
    expect(e.rows.single.progress.spent.minor, 400000);
    expect(e.rows.single.progress.percent, 80);
    // EGP spend outside the budgeted category.
    expect(e.notBudgeted.minor, 200000);
    expect(e.percent, 60);
    expect(e.safePerDay, isNotNull);
    expect(u.hasBudget, isFalse);
    expect(u.rows, isEmpty);
    expect(u.notBudgeted.minor, 5000);
  });

  test('a past cycle has no safe-to-spend', () {
    final d = buildBudgetScreenData(
      cycle: cycle,
      today: CivilDate(2026, 12, 3),
      totals: {egp: totals(egp, 1000, {})},
      basis: {egp: egpM(100)},
      budgets: const [],
      calendarMonth: false,
      hasPrevious: true,
    );
    expect(d.isCurrent, isFalse);
    expect(d.currencies.single.safePerDay, isNull);
  });

  test('no budget keeps the spend and flags empty', () {
    final d = buildBudgetScreenData(
      cycle: cycle,
      today: today,
      totals: {egp: totals(egp, 1000, {})},
      basis: const {},
      budgets: const [],
      calendarMonth: true,
      hasPrevious: false,
    );
    final v = d.currencies.single;
    expect(v.hasBudget, isFalse);
    expect(v.percent, isNull);
    expect(v.spent.minor, 1000);
    expect(d.calendarMonth, isTrue);
  });
}
