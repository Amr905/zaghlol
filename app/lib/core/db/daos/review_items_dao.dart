// T-019: the review queue (database-schema §2.7). Items cascade away with
// their raw message or transaction. Resolving is conditional on the item
// still being open, so two engines (or a double tap) resolve it once.
// Payloads are JSON objects of ids and suggested fields, never message text.
// Writes go through guardWrite; nothing here logs.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `review_items.kind` values.
abstract final class ReviewKind {
  static const String unrecognized = 'unrecognized';
  static const String lowConfidence = 'low_confidence';
  static const String newSender = 'new_sender';
  static const String needsCategory = 'needs_category';
  static const String transferAmbiguous = 'transfer_ambiguous';
  static const String reimbursementSuggestion = 'reimbursement_suggestion';
  static const String subscriptionSuggestion = 'subscription_suggestion';
  static const String fxPairSuggestion = 'fx_pair_suggestion';
  static const String paydaySuggestion = 'payday_suggestion';
}

class ReviewItemsDao {
  ReviewItemsDao(this._db);

  final AppDatabase _db;

  /// Adds an open item. [payload] is stored as a JSON object (≤ 64 KiB).
  Future<void> insert({
    required String id,
    required String kind,
    String? rawMessageId,
    String? txnId,
    Map<String, Object?>? payload,
    required int createdAt,
  }) {
    final encoded = payload == null ? null : jsonEncode(payload);
    return guardWrite(
      () => _db
          .into(_db.reviewItems)
          .insert(
            ReviewItemsCompanion.insert(
              id: id,
              kind: kind,
              rawMessageId: Value(rawMessageId),
              txnId: Value(txnId),
              payload: Value(encoded),
              createdAt: createdAt,
            ),
          ),
    );
  }

  Future<ReviewItemRow?> byId(String id) => (_db.select(
    _db.reviewItems,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Open items (of [kind] when given), oldest first, at most [limit].
  Future<List<ReviewItemRow>> open({String? kind, int limit = 100}) {
    final q = _db.select(_db.reviewItems)
      ..where(
        (r) =>
            r.resolvedAt.isNull() &
            (kind == null ? const Constant(true) : r.kind.equals(kind)),
      )
      ..orderBy([
        (r) => OrderingTerm.asc(r.createdAt),
        (r) => OrderingTerm.asc(r.id),
      ])
      ..limit(limit);
    return q.get();
  }

  Future<int> countOpen() async {
    final row = await _db
        .customSelect(
          'SELECT count(*) AS n FROM review_items WHERE resolved_at IS NULL',
          readsFrom: {_db.reviewItems},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Resolves item [id] with [resolution] (a slug such as `confirmed`,
  /// `dismissed`). Returns true when this call resolved it; false when it
  /// was already resolved or doesn't exist.
  Future<bool> resolve(
    String id, {
    required String resolution,
    required int at,
  }) => guardWrite(() async {
    final changed =
        await (_db.update(
          _db.reviewItems,
        )..where((r) => r.id.equals(id) & r.resolvedAt.isNull())).write(
          ReviewItemsCompanion(
            resolvedAt: Value(at),
            resolution: Value(resolution),
          ),
        );
    return changed == 1;
  });

  /// Deletes items resolved before [cutoff]. Returns the rows deleted.
  Future<int> purgeResolvedBefore(int cutoff) => guardWrite(
    () => (_db.delete(
      _db.reviewItems,
    )..where((r) => r.resolvedAt.isSmallerThanValue(cutoff))).go(),
  );
}

/// The payload of a stored item, or null. A stored value that is not a JSON
/// object is [FormatException] without the text.
Map<String, Object?>? reviewPayloadOf(ReviewItemRow row) {
  final raw = row.payload;
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // fall through
  }
  throw const FormatException('REVIEW_PAYLOAD_CORRUPT');
}
