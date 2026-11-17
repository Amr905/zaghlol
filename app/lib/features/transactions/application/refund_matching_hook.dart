// FU-142: offers every row the ingest stores or edits to refund matching
// (T-090). Runs inside the message's savepoint (PostPersistHook).
// `onPersisted` is idempotent and ignores rows that are not live refunds.
// A matching failure never costs the transaction (the user can still link
// by hand; the next edit tries again).

import '../../ingestion/domain/ingest_ports.dart';
import 'refund_matching.dart';

final class RefundMatchingHook implements PostPersistHook {
  RefundMatchingHook(this._refunds);

  final RefundMatching _refunds;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    try {
      await _refunds.onPersisted(txn.txnId);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
