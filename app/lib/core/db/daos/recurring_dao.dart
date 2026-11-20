// T-018: recurring items and their occurrences (database-schema §2.5,
// FR-SUB-*). Amounts are Money (integer minor units + currency). Writes go
// through guardWrite; nothing here logs.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../app_database.dart';
import 'write_errors.dart';

class RecurringDao {
  RecurringDao(this._db);

  final AppDatabase _db;

  /// Inserts an item; set the amount with `withAmount` (money_columns.dart).
  Future<void> insertItem(RecurringItemsCompanion row) =>
      guardWrite(() => _db.into(_db.recurringItems).insert(row));

  /// A currency change without a new amount would silently re-denominate the
  /// stored amount: it is refused with [CurrencyMismatch] and nothing changes
  /// (like `BudgetsDao.updateLimit`). Set both together with `withAmount`.
  Future<int> updateItem(String id, RecurringItemsCompanion row) => guardWrite(
    () => _db.transaction(() async {
      if (row.currency.present && !row.amountMinor.present) {
        final current = await itemById(id);
        if (current != null && current.currency != row.currency.value) {
          throw CurrencyMismatch(
            Currency.of(row.currency.value),
            Currency.of(current.currency),
          );
        }
      }
      return (_db.update(
        _db.recurringItems,
      )..where((r) => r.id.equals(id))).write(row);
    }),
  );

  Future<RecurringItemRow?> itemById(String id) => (_db.select(
    _db.recurringItems,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Active items due on or before [date] (ISO, local), soonest first.
  Future<List<RecurringItemRow>> activeDueBy(String date) =>
      (_db.select(_db.recurringItems)
            ..where(
              (r) =>
                  r.status.equals('active') &
                  r.nextDueDate.isSmallerOrEqualValue(date),
            )
            ..orderBy([
              (r) => OrderingTerm.asc(r.nextDueDate),
              (r) => OrderingTerm.asc(r.id),
            ]))
          .get();

  /// Deletes item [id] and its occurrences (FK cascade).
  Future<int> deleteItem(String id) => guardWrite(
    () => (_db.delete(_db.recurringItems)..where((r) => r.id.equals(id))).go(),
  );

  /// T-196: remembers that the chain [key] (`merchant|account|currency`, see
  /// `recurringKey`) is not a bill, so detection never adds it again. Writing
  /// a key twice keeps the first time.
  Future<void> rememberDismissal(String key, {required int at}) => guardWrite(
    () => _db
        .into(_db.recurringDismissals)
        .insert(
          RecurringDismissalsCompanion.insert(
            dismissalKey: key,
            dismissedAt: at,
          ),
          mode: InsertMode.insertOrIgnore,
        ),
  );

  /// Every remembered chain key.
  Future<Set<String>> dismissalKeys() async => {
    for (final r in await _db.select(_db.recurringDismissals).get())
      r.dismissalKey,
  };

  /// Inserts or updates the occurrence (item, due date).
  Future<void> upsertOccurrence(RecurringOccurrencesCompanion row) =>
      guardWrite(
        () => _db.into(_db.recurringOccurrences).insertOnConflictUpdate(row),
      );

  Future<List<RecurringOccurrenceRow>> occurrencesOf(String itemId) =>
      (_db.select(_db.recurringOccurrences)
            ..where((o) => o.itemId.equals(itemId))
            ..orderBy([(o) => OrderingTerm.asc(o.dueDate)]))
          .get();
}
