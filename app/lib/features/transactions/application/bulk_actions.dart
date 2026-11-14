// T-079: what the transactions list can do to a selection, in one place.
//
// Deleting goes through [BulkEditUseCase] (one all-or-none transaction with an
// Undo image) and then runs the two removal hooks for every deleted row, so a
// deleted transfer leg or refund/expense never leaves a stale pair or offset
// link behind (FU-127 / FU-142). Nothing here logs; failures are code-only
// exceptions from the use cases.

import 'bulk_edit.dart';
import 'refund_matching.dart';
import 'transfer_pairing.dart';

/// The port the list screen uses (faked in widget tests).
abstract interface class TxnBulkActions {
  Future<BulkEditResult> setCategory(
    Set<String> ids,
    String categoryId, {
    bool alwaysUseForMerchants = false,
  });

  Future<BulkEditResult> setAccount(Set<String> ids, String accountId);

  /// Soft-deletes [ids] and dissolves their transfer pairs and offset links.
  Future<BulkEditResult> delete(Set<String> ids);

  Future<UndoResult> undo(String batchId);
}

class BulkActions implements TxnBulkActions {
  BulkActions({
    required this._bulk,
    required this._pairing,
    required this._refunds,
  });

  final BulkEditUseCase _bulk;
  final TransferPairingUseCase _pairing;
  final RefundMatching _refunds;

  /// Ids of each delete batch, so an Undo can re-pair and re-link them.
  final Map<String, Set<String>> _deleted = {};

  @override
  Future<BulkEditResult> setCategory(
    Set<String> ids,
    String categoryId, {
    bool alwaysUseForMerchants = false,
  }) => _bulk.apply(
    ids,
    SetCategory(categoryId, alwaysUseForMerchants: alwaysUseForMerchants),
  );

  @override
  Future<BulkEditResult> setAccount(Set<String> ids, String accountId) =>
      _bulk.apply(ids, SetAccount(accountId));

  @override
  Future<BulkEditResult> delete(Set<String> ids) async {
    final result = await _bulk.apply(ids, const DeleteTransactions());
    // After the soft delete: free pairs and links of every removed row.
    for (final id in ids) {
      await _pairing.onRemoved(id);
      await _refunds.onRemoved(id);
    }
    _deleted[result.batchId] = {...ids};
    return result;
  }

  @override
  Future<UndoResult> undo(String batchId) async {
    final result = await _bulk.undo(batchId);
    // Restored rows get their pairs and offset links back (idempotent).
    final ids = _deleted.remove(batchId) ?? const <String>{};
    for (final id in ids) {
      await _pairing.onPersisted(id);
      await _refunds.onPersisted(id);
    }
    return result;
  }
}
