// T-079: what the transactions list can do to a selection, in one place.
//
// Deleting goes through [BulkEditUseCase] (one all-or-none transaction with an
// Undo image) and then runs the two removal hooks for every deleted row, so a
// deleted transfer leg or refund/expense never leaves a stale pair or offset
// link behind (FU-127 / FU-142). Nothing here logs; failures are code-only
// exceptions from the use cases.

import 'bulk_edit.dart';
import 'refund_matching.dart';
import 'transaction_editor.dart' show CategorizedHook;
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
  /// An exchange leg takes its other leg and the pair with it (T-281); Undo
  /// puts all of it back.
  Future<BulkEditResult> delete(Set<String> ids);

  Future<UndoResult> undo(String batchId);
}

class BulkActions implements TxnBulkActions {
  BulkActions({
    required this._bulk,
    required this._pairing,
    required this._refunds,
    this.onCategorized,
  });

  final BulkEditUseCase _bulk;
  final TransferPairingUseCase _pairing;
  final RefundMatching _refunds;

  /// FU-141: runs for each re-categorized row after the batch committed
  /// (the merchant-contribution offer). Best effort.
  final CategorizedHook? onCategorized;

  /// Ids of each delete batch, so an Undo can re-pair and re-link them.
  final Map<String, Set<String>> _deleted = {};

  @override
  Future<BulkEditResult> setCategory(
    Set<String> ids,
    String categoryId, {
    bool alwaysUseForMerchants = false,
  }) async {
    final result = await _bulk.apply(
      ids,
      SetCategory(categoryId, alwaysUseForMerchants: alwaysUseForMerchants),
    );
    final hook = onCategorized;
    if (hook != null) {
      for (final id in ids) {
        try {
          await hook(id);
        } on Object {
          // The edit is done; a contribution not queued is not sent.
        }
      }
    }
    return result;
  }

  @override
  Future<BulkEditResult> setAccount(Set<String> ids, String accountId) =>
      _bulk.apply(ids, SetAccount(accountId));

  @override
  Future<BulkEditResult> delete(Set<String> ids) async {
    // T-281: the user deletes what the list shows, and an exchange is one
    // row, so both of its legs and the pair go in the one transaction.
    final result = await _bulk.apply(
      ids,
      const DeleteTransactions(wholeExchanges: true),
    );
    final removed = {...ids, ...result.ids};
    // After the soft delete: free pairs and links of every removed row.
    // FU-132: remember the batch first and give every id its turn, so one
    // failing hook neither loses the Undo ids nor skips the other rows. The
    // first failure is rethrown at the end.
    _deleted[result.batchId] = removed;
    Object? failure;
    StackTrace? trace;
    for (final id in removed) {
      try {
        await _pairing.onRemoved(id);
        await _refunds.onRemoved(id);
      } on Object catch (e, st) {
        failure ??= e;
        trace ??= st;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
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
