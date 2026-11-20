// T-195: offers every credit the ingest stores to the salary matcher, inside
// the message's savepoint (PostPersistHook). A failure never costs the
// transaction: the next housekeeping run reconciles it.

import '../../ingestion/domain/ingest_ports.dart';
import 'salary_matching.dart';

final class SalaryMatchingHook implements PostPersistHook {
  SalaryMatchingHook(this._matching);

  final SalaryMatching _matching;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    // A merge into an existing row changed nothing new to match.
    if (!txn.inserted) return;
    try {
      await _matching.onPersisted(txn.txnId);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
