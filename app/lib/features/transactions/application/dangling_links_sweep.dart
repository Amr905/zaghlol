// FU-253 (FU-142): start-up sweep for transfer pairs and offset (refund /
// reimbursement) links that still point at a soft-deleted leg, left behind
// when a delete path crashed between the soft delete and its `onRemoved`
// hook. Each leg found goes through the same hooks as a normal delete, which
// dissolve the pair / link and free the surviving row. Never deletes or
// edits a transaction itself. Bounded per run; idempotent (a handled link
// is gone, so the next run finds nothing). Nothing here logs.

import 'package:drift/drift.dart' show Variable;

import '../../../core/db/app_database.dart';

/// Legs handled per kind in one run.
const int kSweepLimit = 100;

/// Soft-deleted transactions that still hold a transfer pair.
Future<List<String>> deletedPairLegs(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT DISTINCT t.id AS id FROM transactions t '
        'JOIN transfer_pairs p ON t.id = p.out_txn_id OR t.id = p.in_txn_id '
        'WHERE t.deleted_at IS NOT NULL ORDER BY t.id LIMIT ?1',
        variables: [Variable.withInt(kSweepLimit)],
        readsFrom: {db.transactions, db.transferPairs},
      )
      .get();
  return [for (final r in rows) r.read<String>('id')];
}

/// Soft-deleted transactions that still hold an offset link.
Future<List<String>> deletedOffsetLegs(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT DISTINCT t.id AS id FROM transactions t '
        'JOIN offset_links o ON t.id = o.expense_txn_id '
        'OR t.id = o.source_txn_id '
        'WHERE t.deleted_at IS NOT NULL ORDER BY t.id LIMIT ?1',
        variables: [Variable.withInt(kSweepLimit)],
        readsFrom: {db.transactions, db.offsetLinks},
      )
      .get();
  return [for (final r in rows) r.read<String>('id')];
}

/// Frees links of deleted legs through [onPairRemoved] / [onOffsetRemoved]
/// (`TransferPairingUseCase.onRemoved` / `RefundMatching.onRemoved`). One
/// failing leg never stops the others. Returns how many legs were handled.
Future<int> sweepDanglingLinks(
  AppDatabase db, {
  required Future<void> Function(String txnId) onPairRemoved,
  required Future<void> Function(String txnId) onOffsetRemoved,
  bool Function()? shouldStop,
}) async {
  var handled = 0;
  for (final id in await deletedPairLegs(db)) {
    if (shouldStop?.call() ?? false) return handled;
    try {
      await onPairRemoved(id);
      handled++;
    } on Object {
      // Found again next run.
    }
  }
  for (final id in await deletedOffsetLegs(db)) {
    if (shouldStop?.call() ?? false) return handled;
    try {
      await onOffsetRemoved(id);
      handled++;
    } on Object {
      // Found again next run.
    }
  }
  return handled;
}
