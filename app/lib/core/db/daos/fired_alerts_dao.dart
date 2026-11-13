// T-018: once-only alerts (database-schema §2.5, BR-BUD-02). The primary key
// (kind, subject, period, threshold) is the "fired" fact, so two engines
// racing to fire the same alert get exactly one winner. Nothing here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

class FiredAlertsDao {
  FiredAlertsDao(this._db);

  final AppDatabase _db;

  /// Records the alert and returns true when this call fired it; false when
  /// it had already fired (nothing changes then).
  Future<bool> markFired({
    required String kind,
    required String subjectId,
    required String periodKey,
    int threshold = 0,
    required int at,
  }) => guardWrite(() async {
    // The changed-row count, not the insert id: after an ignored insert,
    // SQLite's last insert rowid still names the previous insert.
    final changed = await _db.customUpdate(
      'INSERT INTO fired_alerts '
      '(kind, subject_id, period_key, threshold, fired_at) '
      'VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT DO NOTHING',
      variables: [
        Variable.withString(kind),
        Variable.withString(subjectId),
        Variable.withString(periodKey),
        Variable.withInt(threshold),
        Variable.withInt(at),
      ],
      updates: {_db.firedAlerts},
      updateKind: UpdateKind.insert,
    );
    return changed == 1;
  });

  /// Releases one fired alert (the platform refused to show it, FU-133).
  Future<void> unmarkFired({
    required String kind,
    required String subjectId,
    required String periodKey,
    int threshold = 0,
  }) => guardWrite(
    () =>
        (_db.delete(_db.firedAlerts)..where(
              (a) =>
                  a.kind.equals(kind) &
                  a.subjectId.equals(subjectId) &
                  a.periodKey.equals(periodKey) &
                  a.threshold.equals(threshold),
            ))
            .go(),
  );

  Future<bool> hasFired({
    required String kind,
    required String subjectId,
    required String periodKey,
    int threshold = 0,
  }) async =>
      await (_db.select(_db.firedAlerts)..where(
            (a) =>
                a.kind.equals(kind) &
                a.subjectId.equals(subjectId) &
                a.periodKey.equals(periodKey) &
                a.threshold.equals(threshold),
          ))
          .getSingleOrNull() !=
      null;

  /// Deletes the alerts of [subjectId] (e.g. a deleted budget). Returns the
  /// rows deleted.
  Future<int> deleteForSubject(String subjectId) => guardWrite(
    () => (_db.delete(
      _db.firedAlerts,
    )..where((a) => a.subjectId.equals(subjectId))).go(),
  );
}
