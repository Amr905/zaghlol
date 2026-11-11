// T-019: voice usage (FR-VOI-04, A-15), bulk-edit undo batches (FR-TXN-06,
// domain-algorithms §14) and the diagnostic log (error-handling-and-
// observability §3.1). Writes go through guardWrite; nothing here logs.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// The `voice_usage.month` key of [local] (a local date-time): `YYYY-MM`.
/// The count resets on the 1st of each calendar month, not on payday (A-15).
String voiceMonthOf(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}';

class VoiceUsageDao {
  VoiceUsageDao(this._db);

  final AppDatabase _db;

  Future<int> countFor(String month) async =>
      (await (_db.select(
        _db.voiceUsage,
      )..where((v) => v.month.equals(month))).getSingleOrNull())?.count ??
      0;

  /// Counts one confirmed voice log in [month] and returns the new count
  /// (Gold: no limit).
  Future<int> increment(String month) => guardWrite(() async {
    final rows = await _db.customWriteReturning(
      'INSERT INTO voice_usage (month, "count") VALUES (?1, 1) '
      'ON CONFLICT (month) DO UPDATE SET "count" = "count" + 1 '
      'RETURNING "count"',
      variables: [Variable.withString(month)],
      updates: {_db.voiceUsage},
      updateKind: UpdateKind.update,
    );
    return rows.single.read<int>('count');
  });

  /// Counts one voice log in [month] only while the count is below [limit]
  /// (free tier, 15). One conditional statement: of many racing callers,
  /// exactly `limit − count` succeed. Returns true when this call counted.
  Future<bool> incrementIfBelow(String month, int limit) {
    if (limit <= 0) return Future.value(false);
    return guardWrite(() async {
      final changed = await _db.customUpdate(
        'INSERT INTO voice_usage (month, "count") VALUES (?1, 1) '
        'ON CONFLICT (month) DO UPDATE SET "count" = "count" + 1 '
        'WHERE "count" < ?2',
        variables: [Variable.withString(month), Variable.withInt(limit)],
        updates: {_db.voiceUsage},
        updateKind: UpdateKind.update,
      );
      return changed == 1;
    });
  }
}

class UndoBatchesDao {
  UndoBatchesDao(this._db);

  final AppDatabase _db;

  /// Stores the before-image [beforeJson] (valid JSON, ≤ 8 MiB) of a bulk
  /// edit. [descriptionKey] is an l10n key, never user text.
  Future<void> insert({
    required String id,
    required int createdAt,
    required String descriptionKey,
    required String beforeJson,
  }) => guardWrite(
    () => _db
        .into(_db.undoBatches)
        .insert(
          UndoBatchesCompanion.insert(
            id: id,
            createdAt: createdAt,
            descriptionKey: descriptionKey,
            beforeJson: beforeJson,
          ),
        ),
  );

  Future<UndoBatchRow?> byId(String id) => (_db.select(
    _db.undoBatches,
  )..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.undoBatches)..where((u) => u.id.equals(id))).go(),
  );

  /// Deletes batches created before [cutoff] (24 h expiry). Returns the
  /// rows deleted.
  Future<int> purgeOlderThan(int cutoff) => guardWrite(
    () => (_db.delete(
      _db.undoBatches,
    )..where((u) => u.createdAt.isSmallerThanValue(cutoff))).go(),
  );
}

/// `diag_log.level` values.
enum DiagLevel { debug, info, warn, error }

class DiagLogDao {
  DiagLogDao(this._db);

  final AppDatabase _db;

  /// Appends one event: [code] is a fixed event code (no spaces), [fields]
  /// a small JSON object (≤ 2 KiB) from T-021's allow-list.
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    Map<String, Object?>? fields,
  }) {
    final encoded = fields == null ? null : jsonEncode(fields);
    return guardWrite(
      () => _db
          .into(_db.diagLog)
          .insert(
            DiagLogCompanion.insert(
              at: at,
              level: level.name,
              code: code,
              fields: Value(encoded),
            ),
          ),
    );
  }

  /// The newest [limit] events, newest first.
  Future<List<DiagLogRow>> recent({int limit = 200}) =>
      (_db.select(_db.diagLog)
            ..orderBy([
              (d) => OrderingTerm.desc(d.at),
              (d) => OrderingTerm.desc(d.id),
            ])
            ..limit(limit))
          .get();

  /// Ring buffer: deletes events before [olderThan], then all but the newest
  /// [keepAtMost], in one transaction. Returns the rows deleted.
  Future<int> prune({required int olderThan, required int keepAtMost}) =>
      guardWrite(
        () => _db.transaction(() async {
          final old = await (_db.delete(
            _db.diagLog,
          )..where((d) => d.at.isSmallerThanValue(olderThan))).go();
          final over = await _db.customUpdate(
            'DELETE FROM diag_log WHERE id NOT IN (SELECT id FROM diag_log '
            'ORDER BY "at" DESC, id DESC LIMIT ?1)',
            variables: [Variable.withInt(keepAtMost < 0 ? 0 : keepAtMost)],
            updates: {_db.diagLog},
            updateKind: UpdateKind.delete,
          );
          return old + over;
        }),
      );

  Future<int> clear() => guardWrite(() => _db.delete(_db.diagLog).go());
}
