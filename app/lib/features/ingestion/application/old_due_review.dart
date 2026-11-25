// T-250 (D-83, FU-295): before batch 67 a card due reminder or statement
// could be auto-saved as spending. Re-parse now offers such a transaction in
// review ("This was a payment-due reminder, not spending — remove it?").
// This is the only code that acts on that offer, and only on the user's tap:
// - Remove: re-checks the offer, then resolves the item and deletes through the shared
//   delete path (TxnBulkActions: undo image, TransactionsChanged, pair and
//   offset clean-up), all in one transaction. Undo restores it.
// - Keep: resolves the item and marks the transaction user-verified.
// Nothing here logs.

import '../../transactions/application/bulk_actions.dart';
import '../data/review_repository.dart';

final class OldDueReview {
  OldDueReview({required this._reviews, required this._txns});

  final ReviewRepository _reviews;
  final TxnBulkActions _txns;

  /// Deletes the transaction of the old-due item [itemId] and resolves the
  /// item. Returns the undo batch id, or null when the offer no longer
  /// applies (resolved, edited or deleted meanwhile): then nothing changed.
  Future<String?> remove(String itemId) => _reviews.inTransaction(() async {
    // FU-316: check, resolve and delete in ONE transaction. The resolve is
    // conditional and comes first, so a Keep that landed after the check
    // wins (nothing is deleted); a failing delete rolls the resolve back, so
    // the item stays open and the Undo always matches what happened.
    final txnId = await _reviews.oldDueTxnToRemove(itemId);
    if (txnId == null) return null;
    if (!await _reviews.markOldDueRemoved(itemId)) return null;
    final r = await _txns.delete({txnId});
    return r.batchId;
  });

  /// Puts back what [remove] deleted (the item stays resolved, so the same
  /// transaction is not offered again).
  Future<void> undoRemove(String batchId) => _txns.undo(batchId);

  /// Keeps the transaction as spending; false when already resolved.
  Future<bool> keep(String itemId) => _reviews.keepOldDue(itemId);
}
