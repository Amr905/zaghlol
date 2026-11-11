// T-018: the cycle summary read-model cache (database-schema §2.5), rebuilt
// on TransactionsChanged by the cycle engine (T-051). One row per (cycle
// start, currency, account filter): totals are per currency, never summed
// across currencies (CLAUDE.md §2.4). Writes go through guardWrite; nothing
// here logs.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import 'write_errors.dart';

class CycleSummariesDao {
  CycleSummariesDao(this._db);

  final AppDatabase _db;

  /// Writes the summary of [cycleStart] (ISO date, local) in the currency of
  /// [income] and [spend], which must match (else [CurrencyMismatch]).
  /// [byCategoryMinor]: category id → spend in minor units of that currency.
  Future<void> upsert({
    required String cycleStart,
    String accountFilter = '*',
    required Money income,
    required Money spend,
    required Map<String, int> byCategoryMinor,
    required int computedAt,
  }) async {
    if (income.currency != spend.currency) {
      throw CurrencyMismatch(income.currency, spend.currency);
    }
    await guardWrite(
      () => _db
          .into(_db.cycleSummaries)
          .insertOnConflictUpdate(
            CycleSummariesCompanion.insert(
              cycleStart: cycleStart,
              currency: income.currency.code,
              accountFilter: Value(accountFilter),
              incomeMinor: income.toStorage().minor,
              spendMinor: spend.toStorage().minor,
              byCategory: jsonEncode(byCategoryMinor),
              computedAt: computedAt,
            ),
          ),
    );
  }

  Future<CycleSummaryRow?> find({
    required String cycleStart,
    required Currency currency,
    String accountFilter = '*',
  }) =>
      (_db.select(_db.cycleSummaries)..where(
            (c) =>
                c.cycleStart.equals(cycleStart) &
                c.currency.equals(currency.code) &
                c.accountFilter.equals(accountFilter),
          ))
          .getSingleOrNull();

  /// Every row of [cycleStart] for [accountFilter].
  Future<List<CycleSummaryRow>> rowsFor({
    required String cycleStart,
    String accountFilter = '*',
  }) =>
      (_db.select(_db.cycleSummaries)..where(
            (c) =>
                c.cycleStart.equals(cycleStart) &
                c.accountFilter.equals(accountFilter),
          ))
          .get();

  /// Replaces the rows of ([cycleStart], [accountFilter]) with [summaries]
  /// (one transaction), so a currency that no longer has activity drops out.
  Future<void> replaceCycle({
    required String cycleStart,
    String accountFilter = '*',
    required Iterable<CycleTotals> summaries,
    required int computedAt,
  }) => guardWrite(
    () => _db.transaction(() async {
      await (_db.delete(_db.cycleSummaries)..where(
            (c) =>
                c.cycleStart.equals(cycleStart) &
                c.accountFilter.equals(accountFilter),
          ))
          .go();
      for (final t in summaries) {
        await upsert(
          cycleStart: cycleStart,
          accountFilter: accountFilter,
          income: t.income,
          spend: t.spend,
          byCategoryMinor: t.byCategoryMinor,
          computedAt: computedAt,
        );
      }
    }),
  );

  /// Drops every account filter of the given cycles. Returns the rows
  /// deleted.
  Future<int> deleteCycles(Iterable<String> cycleStarts) => guardWrite(
    () => (_db.delete(
      _db.cycleSummaries,
    )..where((c) => c.cycleStart.isIn(cycleStarts.toList()))).go(),
  );

  /// Drops every cached summary (a full rebuild follows). Returns the rows
  /// deleted.
  Future<int> clear() => guardWrite(() => _db.delete(_db.cycleSummaries).go());
}

/// The per-category spend of a stored summary, in its currency. A stored
/// value that is not an object of integers is [FormatException] without
/// the text.
Map<String, Money> cycleSpendByCategoryOf(CycleSummaryRow row) {
  final Object? decoded;
  try {
    decoded = jsonDecode(row.byCategory);
  } on FormatException {
    throw const FormatException('CYCLE_SUMMARY_CORRUPT');
  }
  if (decoded is! Map<String, Object?> ||
      decoded.values.any((v) => v is! int)) {
    throw const FormatException('CYCLE_SUMMARY_CORRUPT');
  }
  return {
    for (final e in decoded.entries)
      e.key: Money.fromStorage(e.value! as int, row.currency),
  };
}
