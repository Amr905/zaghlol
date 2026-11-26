// T-356: the auto-category send queue (LLM-CATEGORISE, FR-LCAT-04;
// llm-categorise.md §7). One row per eligible merchant waiting to be sent:
// how many transactions asked for it, when it was first queued and last
// seen, and its retry state. The policies (cap 100, 60 days, back-off) are
// the sender's; this DAO gives them one statement or one transaction each.
// User data: backed up, never uploaded as such. Writes go through
// guardWrite; nothing here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

class LlmCatQueueDao {
  LlmCatQueueDao(this._db);

  final AppDatabase _db;

  /// Queues [merchantNorm] for a transaction seen at [at], or counts one
  /// more transaction for an already queued merchant (`last_seen_at` only
  /// moves forward; `first_queued_at` and the retry state stay).
  Future<void> enqueue(String merchantNorm, {required int at}) => guardWrite(
    () => _db.customUpdate(
      'INSERT INTO llm_cat_queue (merchant_norm, txn_count, first_queued_at, '
      'last_seen_at) VALUES (?1, 1, ?2, ?2) '
      'ON CONFLICT (merchant_norm) DO UPDATE SET '
      'txn_count = llm_cat_queue.txn_count + 1, '
      'last_seen_at = max(llm_cat_queue.last_seen_at, ?2)',
      variables: [Variable.withString(merchantNorm), Variable.withInt(at)],
      updates: {_db.llmCatQueue},
    ),
  );

  /// Rows whose next attempt is due at [now], in send order: most
  /// transactions first, then most recently seen; at most [limit].
  Future<List<LlmCatQueueRow>> due({required int now, int limit = 20}) =>
      guardRead(
        () =>
            (_db.select(_db.llmCatQueue)
                  ..where(
                    (q) =>
                        q.nextAttemptAt.isNull() |
                        q.nextAttemptAt.isSmallerOrEqualValue(now),
                  )
                  ..orderBy([
                    (q) => OrderingTerm.desc(q.txnCount),
                    (q) => OrderingTerm.desc(q.lastSeenAt),
                    (q) => OrderingTerm.asc(q.merchantNorm),
                  ])
                  ..limit(limit))
                .get(),
      );

  /// Every queued row, in send order.
  Future<List<LlmCatQueueRow>> all() => guardRead(
    () =>
        (_db.select(_db.llmCatQueue)..orderBy([
              (q) => OrderingTerm.desc(q.txnCount),
              (q) => OrderingTerm.desc(q.lastSeenAt),
              (q) => OrderingTerm.asc(q.merchantNorm),
            ]))
            .get(),
  );

  Future<int> count() async {
    final row = await guardRead(
      () => _db
          .customSelect(
            'SELECT count(*) AS n FROM llm_cat_queue',
            readsFrom: {_db.llmCatQueue},
          )
          .getSingle(),
    );
    return row.read<int>('n');
  }

  /// Counts one failed attempt for each of [merchantNorms] and sets their
  /// next attempt, in one transaction. Returns the rows changed.
  Future<int> markAttempt(
    Iterable<String> merchantNorms, {
    required int nextAttemptAt,
  }) {
    final list = merchantNorms.toSet().toList();
    if (list.isEmpty) return Future.value(0);
    return guardWrite(
      () => _db.transaction(() async {
        var changed = 0;
        for (final m in list) {
          changed += await _db.customUpdate(
            'UPDATE llm_cat_queue SET attempts = attempts + 1, '
            'next_attempt_at = ?1 WHERE merchant_norm = ?2',
            variables: [
              Variable.withInt(nextAttemptAt),
              Variable.withString(m),
            ],
            updates: {_db.llmCatQueue},
            updateKind: UpdateKind.update,
          );
        }
        return changed;
      }),
    );
  }

  /// Removes [merchantNorms] (answered, or no longer eligible). Returns the
  /// rows deleted.
  Future<int> remove(Iterable<String> merchantNorms) {
    final list = merchantNorms.toSet().toList();
    if (list.isEmpty) return Future.value(0);
    return guardWrite(
      () => _db.transaction(() async {
        var n = 0;
        for (var i = 0; i < list.length; i += 500) {
          final part = list.sublist(
            i,
            i + 500 > list.length ? list.length : i + 500,
          );
          n += await (_db.delete(
            _db.llmCatQueue,
          )..where((q) => q.merchantNorm.isIn(part))).go();
        }
        return n;
      }),
    );
  }

  /// Applies the queue limits in one transaction: drops rows first queued
  /// before [expireBefore], then the oldest-queued rows beyond [maxRows].
  /// Returns the rows dropped.
  Future<int> trim({required int maxRows, required int expireBefore}) {
    if (maxRows < 0) throw ArgumentError.value(maxRows, 'maxRows');
    return guardWrite(
      () => _db.transaction(() async {
        final expired = await _db.customUpdate(
          'DELETE FROM llm_cat_queue WHERE first_queued_at < ?1',
          variables: [Variable.withInt(expireBefore)],
          updates: {_db.llmCatQueue},
          updateKind: UpdateKind.delete,
        );
        final over = await _db.customUpdate(
          'DELETE FROM llm_cat_queue WHERE merchant_norm IN ('
          'SELECT merchant_norm FROM llm_cat_queue '
          'ORDER BY first_queued_at DESC, merchant_norm DESC '
          'LIMIT -1 OFFSET ?1)',
          variables: [Variable.withInt(maxRows)],
          updates: {_db.llmCatQueue},
          updateKind: UpdateKind.delete,
        );
        return expired + over;
      }),
    );
  }

  /// Empties the queue (the feature was switched off). Returns the rows
  /// deleted.
  Future<int> clear() => guardWrite(() => _db.delete(_db.llmCatQueue).go());
}
