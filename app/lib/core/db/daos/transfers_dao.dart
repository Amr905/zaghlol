// T-019: transfer pairs and split participants (database-schema §2.3), the
// two batch-A tables that had no DAO (T-019 AC "all tables have DAO
// coverage"). Pairing rules (PairSelfTransfers) and split arithmetic live in
// the repositories; these are the row primitives. A split share is in the
// expense's currency (no currency column). Writes go through guardWrite;
// nothing here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `transfer_pairs.kind` values.
abstract final class TransferPairKind {
  static const String auto = 'auto';
  static const String manual = 'manual';
  static const String fxConversion = 'fx_conversion';
  static const String cardSettlement = 'card_settlement';
  static const String crossCurrency = 'cross_currency';
}

class TransferPairsDao {
  TransferPairsDao(this._db);

  final AppDatabase _db;

  Future<void> insert(TransferPairsCompanion row) =>
      guardWrite(() => _db.into(_db.transferPairs).insert(row));

  Future<TransferPairRow?> byId(String id) => (_db.select(
    _db.transferPairs,
  )..where((p) => p.id.equals(id))).getSingleOrNull();

  /// The pair that [txnId] is either side of, or null.
  Future<TransferPairRow?> forTransaction(String txnId) =>
      (_db.select(_db.transferPairs)
            ..where((p) => p.outTxnId.equals(txnId) | p.inTxnId.equals(txnId)))
          .getSingleOrNull();

  /// Unpairs: deletes pair [id] (`transactions.transfer_pair_id` becomes
  /// NULL by its FK).
  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.transferPairs)..where((p) => p.id.equals(id))).go(),
  );
}

class SplitParticipantsDao {
  SplitParticipantsDao(this._db);

  final AppDatabase _db;

  Future<void> insert(SplitParticipantsCompanion row) =>
      guardWrite(() => _db.into(_db.splitParticipants).insert(row));

  Future<List<SplitParticipantRow>> forExpense(String expenseTxnId) =>
      (_db.select(_db.splitParticipants)
            ..where((s) => s.expenseTxnId.equals(expenseTxnId))
            ..orderBy([
              (s) => OrderingTerm.asc(s.createdAt),
              (s) => OrderingTerm.asc(s.id),
            ]))
          .get();

  /// Sets the share (minor units of the expense's currency).
  Future<int> updateShare(String id, int shareMinor) => guardWrite(
    () => (_db.update(_db.splitParticipants)..where((s) => s.id.equals(id)))
        .write(SplitParticipantsCompanion(shareMinor: Value(shareMinor))),
  );

  /// Deletes participant [id]; links naming it keep their amount and lose
  /// the participant (FK `ON DELETE SET NULL`).
  Future<int> deleteById(String id) => guardWrite(
    () =>
        (_db.delete(_db.splitParticipants)..where((s) => s.id.equals(id))).go(),
  );
}
