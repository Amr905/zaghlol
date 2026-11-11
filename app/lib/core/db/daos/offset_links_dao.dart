// T-017: refund / reimbursement links (database-schema §2.3; design note §6).
// The sums are enforced by the schema's triggers; this DAO surfaces their
// codes as DbWriteException (OFFSET_EXCEEDS_EXPENSE, OFFSET_EXCEEDS_SOURCE,
// OFFSET_CURRENCY_MISMATCH, OFFSET_PARTICIPANT_MISMATCH). The use case
// (OffsetLinkService) checks first and runs inside its own transaction.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

class OffsetLinksDao {
  OffsetLinksDao(this._db);

  final AppDatabase _db;

  Future<void> insert(OffsetLinksCompanion row) =>
      guardWrite(() => _db.into(_db.offsetLinks).insert(row));

  /// Changes the linked amount (minor units of the expense's currency).
  Future<int> updateAmount(String id, int amountMinor) => guardWrite(
    () => (_db.update(_db.offsetLinks)..where((l) => l.id.equals(id))).write(
      OffsetLinksCompanion(amountMinor: Value(amountMinor)),
    ),
  );

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.offsetLinks)..where((l) => l.id.equals(id))).go(),
  );

  Future<List<OffsetLinkRow>> forExpense(String expenseTxnId) =>
      (_db.select(_db.offsetLinks)
            ..where((l) => l.expenseTxnId.equals(expenseTxnId))
            ..orderBy([(l) => OrderingTerm.asc(l.createdAt)]))
          .get();

  /// Σ linked minor units for [expenseTxnId] (0 when none).
  Future<int> linkedToExpense(String expenseTxnId) => _sum(
    'SELECT coalesce(sum(amount_minor), 0) AS s FROM offset_links '
    'WHERE expense_txn_id = ?',
    expenseTxnId,
  );

  /// Σ linked minor units taken from [sourceTxnId] (0 when none).
  Future<int> linkedFromSource(String sourceTxnId) => _sum(
    'SELECT coalesce(sum(amount_minor), 0) AS s FROM offset_links '
    'WHERE source_txn_id = ?',
    sourceTxnId,
  );

  /// T-017 review m-4 (decision, T-050): a soft-deleted transaction keeps
  /// its links, so Undo restores the offsets untouched; the schema's
  /// triggers count them until purge. Net-spend reads must use these
  /// "active" sums instead, which ignore links whose other side is
  /// soft-deleted (a deleted refund no longer reduces the expense; a
  /// deleted expense has no net spend).
  ///
  /// Σ linked minor units for live [expenseTxnId] from live sources.
  Future<int> activeLinkedToExpense(String expenseTxnId) => _sum(
    'SELECT coalesce(sum(l.amount_minor), 0) AS s FROM offset_links l '
    'JOIN transactions e ON e.id = l.expense_txn_id '
    'JOIN transactions src ON src.id = l.source_txn_id '
    'WHERE l.expense_txn_id = ? AND e.deleted_at IS NULL '
    'AND src.deleted_at IS NULL',
    expenseTxnId,
  );

  /// Σ linked minor units taken from live [sourceTxnId] into live expenses.
  Future<int> activeLinkedFromSource(String sourceTxnId) => _sum(
    'SELECT coalesce(sum(l.amount_minor), 0) AS s FROM offset_links l '
    'JOIN transactions e ON e.id = l.expense_txn_id '
    'JOIN transactions src ON src.id = l.source_txn_id '
    'WHERE l.source_txn_id = ? AND e.deleted_at IS NULL '
    'AND src.deleted_at IS NULL',
    sourceTxnId,
  );

  Future<int> _sum(String sql, String id) async {
    final row = await _db
        .customSelect(
          sql,
          variables: [Variable.withString(id)],
          readsFrom: {_db.offsetLinks, _db.transactions},
        )
        .getSingle();
    return row.read<int>('s');
  }
}
