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

/// The filters of [TransactionsDao.list] in storage terms (epoch ms; stored
/// codes). Empty sets mean "any".
final class TxnQuery {
  const TxnQuery({
    this.from,
    this.to,
    this.accountIds = const {},
    this.categoryIds = const {},
    this.directions = const {},
    this.sources = const {},
    this.currencies = const {},
    this.statuses = const {},
    this.text,
  });

  /// Inclusive lower bound of `occurred_at`.
  final int? from;

  /// Exclusive upper bound of `occurred_at`.
  final int? to;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Set<String> directions;
  final Set<String> sources;
  final Set<String> currencies;
  final Set<String> statuses;
  final String? text;
}

final class _Built {
  _Built(this.join, this.where, this.args, this.usesFts, this.short);
  final String join;
  final String where;
  final List<Variable> args;
  final bool usesFts;
  final bool short;

  Set<ResultSetImplementation<dynamic, dynamic>> reads(AppDatabase db) => {
    db.transactions,
    if (usesFts) db.transactionsFtsSrc,
    if (usesFts) db.transactionsFts,
    if (usesFts) db.transactionsFtsShort,
  };
}

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

  /// Soft delete for Undo (FR-TXN-06). Only a live row changes: an already
  /// deleted row keeps its original `deleted_at` (the purge clock). Returns
  /// the number of rows changed (0 or 1).
  Future<int> softDelete(String id, {required int at}) => guardWrite(
    () =>
        (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
          TransactionsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
        ),
  );

  /// Undo of [softDelete]. Only a soft-deleted row changes (0 or 1).
  Future<int> restore(String id, {required int at}) => guardWrite(
    () =>
        (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNotNull())).write(
          TransactionsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(at),
          ),
        ),
  );

  /// Hard-deletes rows soft-deleted at or before [cutoff] (epoch ms). Rows
  /// that were never soft-deleted are untouched. The schema's cascades
  /// remove their transfer pairs, offset links and split participants; the
  /// triggers remove their search rows. Returns the number removed.
  Future<int> purgeDeletedAtOrBefore(int cutoff) => guardWrite(
    () =>
        (_db.delete(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNotNull() &
                  t.deletedAt.isSmallerOrEqualValue(cutoff),
            ))
            .go(),
  );

  /// Runs [body] in one database transaction (all or none).
  Future<T> inTransaction<T>(Future<T> Function() body) =>
      guardWrite(() => _db.transaction(body));

  /// Live transactions matching [q], newest first (FR-TXN-01).
  Future<List<TransactionRow>> list(
    TxnQuery q, {
    required int limit,
    int offset = 0,
  }) async {
    final built = _build(q);
    final rows = await guardRead(
      () => _db
          .customSelect(
            'SELECT t.* FROM transactions t${built.join} '
            'WHERE ${built.where} '
            'ORDER BY t.occurred_at DESC, t.id LIMIT ? OFFSET ?',
            variables: [
              ...built.args,
              Variable.withInt(limit.clamp(0, maxSearchLimit)),
              Variable.withInt(offset < 0 ? 0 : offset),
            ],
            readsFrom: built.reads(_db),
          )
          .get(),
    );
    return [for (final r in rows) _db.transactions.map(r.data)];
  }

  /// How many live transactions match [q].
  Future<int> countMatching(TxnQuery q) async {
    final built = _build(q);
    final row = await guardRead(
      () => _db
          .customSelect(
            'SELECT count(*) AS c FROM transactions t${built.join} '
            'WHERE ${built.where}',
            variables: built.args,
            readsFrom: built.reads(_db),
          )
          .getSingle(),
    );
    return row.read<int>('c');
  }

  /// The SQL for [q]. Every value is a bound parameter; the text is never
  /// interpolated. A text of 1–2 digits (either digit system) also matches
  /// amounts whose whole-unit part equals the number ("50" finds 50.00),
  /// because the trigram table needs three characters and the short table
  /// holds names only.
  _Built _build(TxnQuery q) {
    final where = <String>['t.deleted_at IS NULL'];
    final args = <Variable>[];
    void inList(String column, Iterable<Object> values) {
      if (values.isEmpty) return;
      where.add('$column IN (${List.filled(values.length, '?').join(',')})');
      for (final v in values) {
        args.add(v is int ? Variable.withInt(v) : Variable.withString('$v'));
      }
    }

    if (q.from != null) {
      where.add('t.occurred_at >= ?');
      args.add(Variable.withInt(q.from!));
    }
    if (q.to != null) {
      where.add('t.occurred_at < ?');
      args.add(Variable.withInt(q.to!));
    }
    inList('t.account_id', q.accountIds);
    inList('t.category_id', q.categoryIds);
    inList('t.direction', q.directions);
    inList('t.source', q.sources);
    inList('t.currency', q.currencies);
    inList('t.status', q.statuses);

    var join = '';
    var short = false;
    final text = q.text == null ? '' : _clip(_sanitize(q.text!).trim());
    if (text.isNotEmpty) {
      join = ' JOIN transactions_fts_src s ON s.txn_id = t.id';
      final phrase = '"${text.replaceAll('"', '""')}"';
      short = text.runes.length < trigramMinRunes;
      if (!short) {
        where.add(
          's.id IN (SELECT rowid FROM transactions_fts '
          'WHERE transactions_fts MATCH ?)',
        );
        args.add(Variable.withString(phrase));
      } else {
        final digits = _latinDigits(text);
        final isNumber = RegExp(r'^[0-9]{1,2}$').hasMatch(digits);
        final names =
            's.id IN (SELECT rowid FROM transactions_fts_short '
            'WHERE transactions_fts_short MATCH ?)';
        args.add(Variable.withString('$phrase*'));
        if (isNumber) {
          final n = int.parse(digits);
          // "50.00 ٥٠٫٠٠" (exponent > 0) or "50 ٥٠" (exponent 0).
          where.add('($names OR s.amount_text LIKE ? OR s.amount_text LIKE ?)');
          args
            ..add(Variable.withString('$n.%'))
            ..add(Variable.withString('$n %'));
        } else {
          where.add(names);
        }
      }
    }
    return _Built(join, where.join(' AND '), args, text.isNotEmpty, short);
  }

  static String _latinDigits(String text) {
    final out = StringBuffer();
    for (final c in text.runes) {
      if (c >= 0x0660 && c <= 0x0669) {
        out.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        out.writeCharCode(0x30 + c - 0x06F0);
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

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
  /// (`"`, `*`, `NEAR`, `AND`, column filters) is matched literally. C0/C1
  /// control characters (incl. NUL) and lone surrogates become spaces
  /// first. A database failure is a code-only [DbReadException] that never
  /// carries the query.
  Future<List<TransactionRow>> search(String query, {int limit = 100}) async {
    final text = _clip(_sanitize(query).trim());
    if (text.isEmpty || limit <= 0) return const [];
    final short = text.runes.length < trigramMinRunes;
    final phrase = '"${text.replaceAll('"', '""')}"';
    final fts = short ? 'transactions_fts_short' : 'transactions_fts';
    final rows = await guardRead(
      () => _db
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
          .get(),
    );
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

  /// C0 (incl. NUL), DEL, C1 and lone surrogates: FTS5 fails on NUL
  /// ("unterminated string"), and none of them can match indexed text.
  static final RegExp _unsafe = RegExp(
    r'[\u0000-\u001F\u007F-\u009F]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|'
    r'(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
  );

  static String _sanitize(String text) => text.replaceAll(_unsafe, ' ');

  static String _clip(String text) {
    final runes = text.runes;
    if (runes.length <= maxSearchQueryRunes) return text;
    return String.fromCharCodes(runes.take(maxSearchQueryRunes)).trim();
  }
}
