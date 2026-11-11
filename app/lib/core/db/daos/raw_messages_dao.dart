// T-017: raw messages (database-schema §2.2). `body` is sensitive: it is
// only ever bound as a parameter, never logged, never put into an error
// (guardWrite drops the SqliteException that would carry it).

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

class RawMessagesDao {
  RawMessagesDao(this._db);

  final AppDatabase _db;

  /// Inserts [row] unless a message with the same `body_hash` exists
  /// (BR-ING-02 rule 1). Returns true when inserted, false for a duplicate.
  /// Any other refused write (a CHECK, a duplicate id) is a
  /// DbWriteException.
  Future<bool> insertIfNew(RawMessagesCompanion row) => guardWrite(() async {
    final inserted = await _db
        .into(_db.rawMessages)
        .insertReturningOrNull(
          row,
          onConflict: DoNothing(target: [_db.rawMessages.bodyHash]),
        );
    return inserted != null;
  });

  Future<RawMessageRow?> byId(String id) => (_db.select(
    _db.rawMessages,
  )..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<bool> hashExists(String bodyHash) async =>
      await (_db.selectOnly(_db.rawMessages)
            ..addColumns([_db.rawMessages.id])
            ..where(_db.rawMessages.bodyHash.equals(bodyHash))
            ..limit(1))
          .getSingleOrNull() !=
      null;
}
