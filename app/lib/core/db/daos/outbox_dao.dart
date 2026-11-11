// T-019: the upload outbox (database-schema §2.8, backend-api §4.2). Rows
// hold only what BR-SYNC-03 allows (contributions, bank requests, purchase
// verification); the payload is a JSON object. Sent rows are deleted inside
// the sync apply transaction; turning contribution opt-in off deletes the
// queued contributions (EC-48). Writes go through guardWrite; nothing here
// logs.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `outbox.kind` values.
abstract final class OutboxKind {
  static const String contribution = 'contribution';
  static const String bankRequest = 'bank_request';
  static const String purchaseVerify = 'purchase_verify';
}

class OutboxDao {
  OutboxDao(this._db);

  final AppDatabase _db;

  /// Queues [payload] (encoded as a JSON object, ≤ 64 KiB).
  Future<void> enqueue({
    required String id,
    required String kind,
    required Map<String, Object?> payload,
    required int createdAt,
  }) {
    final encoded = jsonEncode(payload);
    return guardWrite(
      () => _db
          .into(_db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: id,
              kind: kind,
              payload: encoded,
              createdAt: createdAt,
            ),
          ),
    );
  }

  /// Rows of [kind] (all kinds when null) whose next attempt is due at
  /// [now], oldest first, at most [limit].
  Future<List<OutboxRow>> due({
    required int now,
    String? kind,
    int limit = 50,
  }) {
    final q = _db.select(_db.outbox)
      ..where(
        (o) =>
            (o.nextAttemptAt.isNull() |
                o.nextAttemptAt.isSmallerOrEqualValue(now)) &
            (kind == null ? const Constant(true) : o.kind.equals(kind)),
      )
      ..orderBy([
        (o) => OrderingTerm.asc(o.createdAt),
        (o) => OrderingTerm.asc(o.id),
      ])
      ..limit(limit);
    return q.get();
  }

  /// Counts one failed attempt of [id] and sets its next attempt.
  Future<int> markAttempt(String id, {required int nextAttemptAt}) =>
      guardWrite(
        () => _db.customUpdate(
          'UPDATE outbox SET attempts = attempts + 1, next_attempt_at = ?1 '
          'WHERE id = ?2',
          variables: [Variable.withInt(nextAttemptAt), Variable.withString(id)],
          updates: {_db.outbox},
          updateKind: UpdateKind.update,
        ),
      );

  /// Deletes the sent rows [ids]. Returns the rows deleted.
  Future<int> deleteIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(0);
    return guardWrite(
      () => (_db.delete(_db.outbox)..where((o) => o.id.isIn(list))).go(),
    );
  }

  /// Deletes every queued row of [kind] (EC-48). Returns the rows deleted.
  Future<int> deleteKind(String kind) => guardWrite(
    () => (_db.delete(_db.outbox)..where((o) => o.kind.equals(kind))).go(),
  );
}
