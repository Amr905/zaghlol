// FU-136: a corrupt budget row maps to null instead of throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/budget/data/budget_mapper.dart';

BudgetRow row({
  String currency = 'EGP',
  int limit = 10000,
  String thresholds = '[80,100]',
}) => BudgetRow(
  id: 'b',
  categoryId: 'food',
  currency: currency,
  limitMinor: limit,
  period: 'monthly',
  rollover: 0,
  thresholds: thresholds,
  createdAt: 0,
);

void main() {
  test('a good row maps', () {
    expect(tryBudgetSpecOf(row())!.limit.minor, 10000);
  });
  test('unknown currency, bad amount and bad thresholds map to null', () {
    expect(tryBudgetSpecOf(row(currency: 'XXQ')), isNull);
    expect(tryBudgetSpecOf(row(currency: 'egp')), isNull);
    expect(tryBudgetSpecOf(row(limit: 1 << 62)), isNull);
    expect(tryBudgetSpecOf(row(thresholds: 'not json')), isNull);
    expect(tryBudgetSpecOf(row(thresholds: '["a"]')), isNull);
  });
}
