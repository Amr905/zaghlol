// T-246 (D-81): after a credit is stored, lets the payday follow the salary
// (inside the message's savepoint, like the salary matcher). Only a stored
// salary credit runs the rule (FU-296 m-1). A failure never
// costs the transaction: the daily housekeeping job runs the same rule.

import '../../ingestion/domain/ingest_ports.dart';
import 'payday_auto_service.dart';

final class PaydayAutoHook implements PostPersistHook {
  PaydayAutoHook(this._service);

  final PaydayAutoService _service;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    if (!txn.inserted) return;
    try {
      await _service.onPersisted(txn.txnId);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
