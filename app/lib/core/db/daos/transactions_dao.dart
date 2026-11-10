// T-017: transactions and search (database-schema §2.2; design note §5).
// The FTS tables are maintained by triggers (financial.drift); this DAO only
// reads them. The search text is bound as a parameter, never interpolated,
// and never logged.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// Longest search text used, in Unicode code points; longer input is cut.
const int maxSearchQueryRunes = 64;

/// Largest page [TransactionsDao.search] returns.
const int maxSearchLimit = 500;

/// Queries shorter than this (in code points) use the word-prefix table:
/// trigram matching needs three characters (T-016 §8(b)).
const int trigramMinRunes = 3;

class TransactionsDao {
  TransactionsDao(this._db);

  final AppDatabase _db;

  Future<void> insert(TransactionsCompanion row) =>
      guardWrite(() => _db.into(_db.transactions).insert(row));

  /// Writes the present fields of [row] to transaction [id]. Returns the
  /// number of rows changed (0 or 1).
  Future<int> updateById(String id, TransactionsCompanion row) => guardWrite(
    () => (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(id))).write(row),
  );

  /// Soft delete for Undo (FR-TXN-06).
  Future<int> softDelete(String id, {required int at}) => updateById(
    id,
    TransactionsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
  );

  Future<TransactionRow?> byId(String id) => (_db.select(
    _db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Transactions whose merchant, counterparty, note or amount text contains
  /// [query] (FR-TXN-01), newest first, soft-deleted rows excluded.
  ///
  /// Three or more characters: substring match on `transactions_fts`
  /// (trigram, case- and Latin-diacritic-insensitive; amounts in Latin and
  /// Arabic-Indic digits). One or two characters: word-prefix match on
  /// merchant and counterparty in `transactions_fts_short` (digits-only
  /// short queries find nothing there: amounts are not in that table).
  /// The text is trimmed and cut to [maxSearchQueryRunes]; FTS5 syntax in it
  /// (`"`, `*`, `NEAR`, `AND`, column filters) is matched literally.
  Future<List<TransactionRow>> search(String query, {int limit = 100}) async {
    final text = _clip(query.trim());
    if (text.isEmpty || limit <= 0) return const [];
    final short = text.runes.length < trigramMinRunes;
    final phrase = '"${text.replaceAll('"', '""')}"';
    final fts = short ? 'transactions_fts_short' : 'transactions_fts';
    final rows = await _db
        .customSelect(
          'SELECT t.* FROM $fts f '
          'JOIN transactions_fts_src s ON s.id = f.rowid '
          'JOIN transactions t ON t.id = s.txn_id '
          'WHERE $fts MATCH ?1 AND t.deleted_at IS NULL '
          'ORDER BY t.occurred_at DESC, t.id '
          'LIMIT ?2',
          variables: [
            Variable.withString(short ? '$phrase*' : phrase),
            Variable.withInt(limit > maxSearchLimit ? maxSearchLimit : limit),
          ],
          readsFrom: {
            _db.transactions,
            _db.transactionsFtsSrc,
            if (short) _db.transactionsFtsShort else _db.transactionsFts,
          },
        )
        .get();
    return [for (final r in rows) _db.transactions.map(r.data)];
  }

  /// Rebuilds both search indexes from `transactions_fts_src` (recovery
  /// only; the triggers keep them in sync).
  Future<void> rebuildSearchIndexes() => guardWrite(
    () => _db.transaction(() async {
      await _db.customStatement(
        "INSERT INTO transactions_fts (transactions_fts) VALUES ('rebuild')",
      );
      await _db.customStatement(
        'INSERT INTO transactions_fts_short (transactions_fts_short) '
        "VALUES ('rebuild')",
      );
    }),
  );

  static String _clip(String text) {
    final runes = text.runes;
    if (runes.length <= maxSearchQueryRunes) return text;
    return String.fromCharCodes(runes.take(maxSearchQueryRunes)).trim();
  }
}
