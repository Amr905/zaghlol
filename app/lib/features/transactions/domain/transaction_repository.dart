// T-050: the port every screen reads and writes transactions through
// (architecture §4.1). Implemented in data/.

import 'transaction.dart';

/// Days a soft-deleted transaction stays restorable (FR-TXN-06; schema §2.2).
const int softDeleteRetentionDays = 30;

abstract interface class TransactionRepository {
  /// Live (not soft-deleted) transactions matching [filter] and the
  /// optional search [text] (merchant, counterparty, note, amount;
  /// Latin and Arabic-Indic digits), newest first.
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  });

  /// The number of rows [query] would return without paging.
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  });

  /// A transaction by id; soft-deleted rows only when [includeDeleted].
  Future<TransactionRecord?> byId(String id, {bool includeDeleted = false});

  /// Stores [txn] as user-verified and returns it.
  Future<TransactionRecord> add(NewTransaction txn);

  /// Applies [edit] to a live row and marks it user-verified.
  /// Throws [TransactionsException] `TXN_NOT_FOUND` for a missing or
  /// soft-deleted row.
  Future<TransactionRecord> edit(String id, TransactionEdit edit);

  /// Soft-deletes live rows in one transaction (all or none). Throws
  /// `TXN_NOT_FOUND` when any id is not a live row.
  Future<void> softDelete(Iterable<String> ids);

  /// Undo: restores soft-deleted rows in one transaction (all or none).
  /// Throws `TXN_NOT_FOUND` (purged or unknown) or `TXN_NOT_DELETED`.
  Future<void> restore(Iterable<String> ids);

  /// Hard-deletes rows soft-deleted at least [softDeleteRetentionDays]
  /// days ago. Returns how many were removed. Idempotent.
  Future<int> purgeExpired();
}
