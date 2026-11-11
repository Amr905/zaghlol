// T-018: budgets (database-schema §2.5, FR-BUD-*). One currency per budget
// (FR-BUD-02): the limit is a Money and its currency is the row's; a change
// of limit in another currency is refused before any SQL. A NULL category is
// the overall budget (A-16), at most one per currency and period
// (ux_budgets_overall). Writes go through guardWrite; nothing here logs.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import '../money_columns.dart';
import 'write_errors.dart';

/// `budgets.period` values (FR-BUD-06).
abstract final class BudgetPeriod {
  static const String cycle = 'cycle';
  static const String annual = 'annual';
}

/// Default alert thresholds, percent of the limit (BR-BUD-02).
const List<int> defaultBudgetThresholds = [80, 100];

/// Most thresholds per budget, and the largest one (percent).
const int maxBudgetThresholds = 10;
const int maxBudgetThresholdPercent = 1000;

class BudgetsDao {
  BudgetsDao(this._db);

  final AppDatabase _db;

  /// Inserts a budget. [thresholds]: 1–[maxBudgetThresholds] distinct
  /// percentages in 1..[maxBudgetThresholdPercent] (else [ArgumentError]),
  /// stored sorted as a JSON array.
  Future<void> insert({
    required String id,
    String? categoryId,
    required Money limit,
    required String period,
    bool rollover = false,
    List<int> thresholds = defaultBudgetThresholds,
    required int createdAt,
  }) {
    final encoded = _encodeThresholds(thresholds);
    final s = limit.toStorage();
    return guardWrite(
      () => _db
          .into(_db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: id,
              categoryId: Value(categoryId),
              currency: s.currency,
              limitMinor: s.minor,
              period: period,
              rollover: Value(rollover ? 1 : 0),
              thresholds: Value(encoded),
              createdAt: createdAt,
            ),
          ),
    );
  }

  Future<BudgetRow?> byId(String id) => (_db.select(
    _db.budgets,
  )..where((b) => b.id.equals(id))).getSingleOrNull();

  /// The budgets in [currency], overall first, then by category id.
  Future<List<BudgetRow>> inCurrency(Currency currency) =>
      (_db.select(_db.budgets)
            ..where((b) => b.currency.equals(currency.code))
            ..orderBy([
              (b) => OrderingTerm(
                expression: b.categoryId,
                nulls: NullsOrder.first,
              ),
            ]))
          .get();

  /// Sets the limit of budget [id]. [limit] must be in the budget's
  /// currency, else [CurrencyMismatch] and nothing changes. Returns the
  /// rows changed (0 when [id] doesn't exist).
  Future<int> updateLimit(String id, Money limit) => guardWrite(
    () => _db.transaction(() async {
      final row = await byId(id);
      if (row == null) return 0;
      final current = row.limit.currency;
      if (current != limit.currency) {
        throw CurrencyMismatch(limit.currency, current);
      }
      return (_db.update(_db.budgets)..where((b) => b.id.equals(id))).write(
        BudgetsCompanion(limitMinor: Value(limit.toStorage().minor)),
      );
    }),
  );

  Future<int> setThresholds(String id, List<int> thresholds) {
    final encoded = _encodeThresholds(thresholds);
    return guardWrite(
      () => (_db.update(_db.budgets)..where((b) => b.id.equals(id))).write(
        BudgetsCompanion(thresholds: Value(encoded)),
      ),
    );
  }

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go(),
  );

  static String _encodeThresholds(List<int> thresholds) {
    final sorted = thresholds.toSet().toList()..sort();
    if (sorted.isEmpty ||
        sorted.length != thresholds.length ||
        sorted.length > maxBudgetThresholds ||
        sorted.first < 1 ||
        sorted.last > maxBudgetThresholdPercent) {
      throw ArgumentError('invalid budget thresholds', 'thresholds');
    }
    return jsonEncode(sorted);
  }
}

/// The thresholds of a stored budget (percent, ascending). A stored value
/// that is not a list of integers is [FormatException] without the text.
List<int> budgetThresholdsOf(BudgetRow row) {
  final Object? decoded;
  try {
    decoded = jsonDecode(row.thresholds);
  } on FormatException {
    throw const FormatException('BUDGET_THRESHOLDS_CORRUPT');
  }
  if (decoded is! List || decoded.any((e) => e is! int)) {
    throw const FormatException('BUDGET_THRESHOLDS_CORRUPT');
  }
  return [for (final e in decoded) e as int];
}
