// T-080: the extra columns S-12 shows beyond [TransactionRecord]: reference,
// balance after, parser facts and the raw message ("How Zaghlol read this"),
// plus the other leg of an own-account transfer. Read-only. The raw body is
// sensitive: it is handed to the screen and never logged.

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/raw_messages_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

/// Everything S-12 needs for one transaction.
final class TxnDetail {
  const TxnDetail({
    required this.record,
    this.referenceNo,
    this.balanceAfter,
    this.templateId,
    this.parseConfidence,
    this.rawBody,
    this.counterpart,
  });

  final TransactionRecord record;
  final String? referenceNo;
  final Money? balanceAfter;
  final String? templateId;

  /// 0..1; a parser score, not money.
  final double? parseConfidence;

  /// The original message text; null for manual rows or when it was purged.
  final String? rawBody;

  /// The other leg when this row is half of a transfer pair.
  final TransactionRecord? counterpart;
}

class TransactionDetailReader {
  TransactionDetailReader(this._db, this._repo);

  final AppDatabase _db;
  final TransactionRepository _repo;

  /// Null when the row is missing or soft-deleted ("no longer exists").
  Future<TxnDetail?> read(String id) async {
    final record = await _repo.byId(id);
    if (record == null) return null;
    final row = await TransactionsDao(_db).byId(id);
    if (row == null) return null;
    String? body;
    final rawId = row.rawMessageId;
    if (rawId != null) body = (await RawMessagesDao(_db).byId(rawId))?.body;
    TransactionRecord? other;
    final pair = row.transferPairId;
    if (pair != null) {
      final legs =
          await (_db.select(_db.transactions)..where(
                (t) => t.transferPairId.equals(pair) & t.id.equals(id).not(),
              ))
              .get();
      for (final leg in legs) {
        if (leg.deletedAt == null) {
          other = await _repo.byId(leg.id);
          break;
        }
      }
    }
    final bal = row.balanceAfterMinor;
    return TxnDetail(
      record: record,
      referenceNo: row.referenceNo,
      balanceAfter: bal == null
          ? null
          : Money.tryMinor(record.amount.currency, bal),
      templateId: row.templateId,
      parseConfidence: row.parseConfidence,
      rawBody: body,
      counterpart: other,
    );
  }
}
