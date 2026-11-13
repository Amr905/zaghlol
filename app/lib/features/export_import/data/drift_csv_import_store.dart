// T-155: Drift implementation of [CsvImportStore]. Inserts only (never
// updates or deletes); the whole import runs in one database transaction.
// Rows get source `csv`, are user-verified, and keep the exported status.
// Nothing here logs.

import 'package:drift/drift.dart' show Value;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/money_columns.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show IdGenerator, newUuidV4;
import '../../transactions/domain/transaction.dart';
import '../application/import_csv.dart';

class DriftCsvImportStore implements CsvImportStore {
  DriftCsvImportStore(
    this._db,
    this._txns,
    this._accounts, {
    DateTime Function()? clock,
    IdGenerator? newId,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4;

  final AppDatabase _db;
  final TransactionsDao _txns;
  final AccountsDao _accounts;
  final DateTime Function() _now;
  final IdGenerator _newId;

  @override
  Future<T> inWriteTransaction<T>(Future<T> Function() body) =>
      _txns.inTransaction(body);

  @override
  Future<Set<String>> accountIds() async => {
    for (final a in await _accounts.listLive(includeHidden: true)) a.id,
  };

  @override
  Future<Set<String>> categoryIds() async => {
    for (final c in await _db.select(_db.categories).get()) c.id,
  };

  @override
  Future<List<ExistingTxnKey>> existingAt(
    String accountId,
    int occurredAtMs,
  ) async {
    final rows = await _txns.list(
      TxnQuery(
        from: occurredAtMs,
        to: occurredAtMs + 1,
        accountIds: {accountId},
      ),
      limit: 500,
    );
    return [
      for (final r in rows)
        ExistingTxnKey(
          direction: TxnDirection.fromCode(r.direction),
          amount: moneyOf(r.amountMinor, r.currency),
          merchant: r.merchantRaw,
        ),
    ];
  }

  @override
  Future<String> insert(ImportedTxn row) async {
    final now = _now().toUtc().millisecondsSinceEpoch;
    final amount = row.amount.toStorage();
    final original = row.originalAmount?.toStorage();
    final id = _newId();
    await _txns.insert(
      TransactionsCompanion.insert(
        id: id,
        accountId: row.accountId,
        source: TxnSource.csv.code,
        direction: row.direction.code,
        status: Value(row.status.code),
        amountMinor: amount.minor,
        currency: amount.currency,
        originalAmountMinor: Value(original?.minor),
        originalCurrency: Value(original?.currency),
        occurredAt: row.occurredAt.toUtc().millisecondsSinceEpoch,
        occurredTzOffsetMin: row.occurredTzOffsetMin,
        merchantRaw: Value(row.merchant),
        categoryId: Value(row.categoryId),
        categorySource: row.categoryId == null ? 'none' : 'user',
        isUserVerified: const Value(1),
        note: Value(row.note),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }
}
