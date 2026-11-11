// T-046: the database port of IngestRawMessages. Every method except
// [IngestStorePort.inWriteTransaction] is called inside the batch's write
// transaction (`BEGIN IMMEDIATE`), so all dedupe and merge reads see a
// state no other connection can change before the commit (design note §10).
// Implemented by data/drift_ingest_store.dart. Failures are code-only
// (DbWriteException, DbReadException).

import '../domain/ingest_records.dart';

abstract interface class IngestStorePort {
  /// Runs [body] in one write transaction; all or nothing.
  Future<T> inWriteTransaction<T>(Future<T> Function() body);

  /// Runs [body] in a savepoint of the current transaction. A throw rolls
  /// back only [body]'s writes and is rethrown; the outer transaction
  /// continues.
  Future<T> inSavepoint<T>(Future<T> Function() body);

  /// Step 0: ignore rules, capture senders, custom template senders and
  /// the settings ingest needs.
  Future<BatchContext> readContext();

  /// Base-only fallback of the Guard re-check (design note §9).
  Future<bool> isIgnored({
    required String institutionCode,
    required String? last4,
    required String channel,
  });

  Future<bool> hashExists(String bodyHash);

  /// False when a row with the same `body_hash` exists (race loser).
  Future<bool> insertRaw(RawInsert row);

  /// Same dedupe key, `occurred_at` in [fromMs, toMs]; soft-deleted rows
  /// included.
  Future<List<TxnCandidate>> crossChannelCandidates({
    required String dedupeKey,
    required int fromMs,
    required int toMs,
  });

  /// Live expense transactions of [institution] in [currency] with
  /// [status], `occurred_at` in [fromMs, toMs].
  Future<List<TxnCandidate>> statusCandidates({
    required String institution,
    required String currency,
    required String status,
    required int fromMs,
    required int toMs,
  });

  Future<void> insertTxn(TxnInsert row);

  /// Applies [patch] to [txnId] and sets `updated_at`. Returns rows changed.
  Future<int> updateTxn(String txnId, TxnPatch patch, {required int atMs});

  Future<void> insertReview({
    required String id,
    required String kind,
    required int createdAtMs,
    String? rawMessageId,
    String? txnId,
    Map<String, Object?>? payload,
  });
}
