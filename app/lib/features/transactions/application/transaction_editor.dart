// T-080: what S-13 saves through. Edits and adds go through the repository;
// afterwards own-transfer pairing and refund matching run for the stored row
// (`onPersisted`). An amount change repairs offset links inside the edit's
// own transaction (EC-40, see DriftTransactionRepository). Code-only
// failures; nothing here logs.

import '../data/drift_transaction_repository.dart';
import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';
import 'refund_matching.dart';
import 'transfer_pairing.dart';

/// What the editor sheet calls (faked in widget tests).
abstract interface class TxnEditorPort {
  /// Stores [legs] (one row, or the two legs of an own transfer, out leg
  /// first) and returns the ids in the same order.
  Future<List<String>> add(List<NewTransaction> legs);

  /// Applies [edit]; the result lists offset links the new amount removed.
  Future<EditOutcome> update(String id, TransactionEdit edit);
}

/// Runs after the user gave a stored transaction a category (FU-141: the
/// merchant-contribution offer). Best effort.
typedef CategorizedHook = Future<void> Function(String txnId);

class TransactionEditor implements TxnEditorPort {
  TransactionEditor(
    this._repo,
    this._pairing,
    this._refunds, {
    this.onCategorized,
  });

  final TransactionRepository _repo;
  final TransferPairingUseCase _pairing;
  final RefundMatching _refunds;
  final CategorizedHook? onCategorized;

  @override
  Future<List<String>> add(List<NewTransaction> legs) async {
    final ids = <String>[];
    for (final leg in legs) {
      ids.add((await _repo.add(leg)).id);
    }
    await _afterSave(ids.first, legs.first.direction);
    if (legs.first.categoryId != null) await _categorized(ids.first);
    return ids;
  }

  @override
  Future<EditOutcome> update(String id, TransactionEdit edit) async {
    final r = _repo;
    final outcome = r is DriftTransactionRepository
        ? await r.editWithOutcome(id, edit)
        : EditOutcome(await r.edit(id, edit), const []);
    await _afterSave(id, outcome.record.direction);
    if (edit.categoryId?.value != null) await _categorized(id);
    return outcome;
  }

  Future<void> _categorized(String id) async {
    final hook = onCategorized;
    if (hook == null) return;
    try {
      await hook(id);
    } on Object {
      // The save is done; a contribution that could not be queued (queue
      // full, database busy) is simply not sent.
    }
  }

  Future<void> _afterSave(String id, TxnDirection direction) async {
    if (direction == TxnDirection.transferOut ||
        direction == TxnDirection.transferIn) {
      await _pairing.onPersisted(id);
    } else if (direction == TxnDirection.refund) {
      await _refunds.onPersisted(id);
    }
  }
}
