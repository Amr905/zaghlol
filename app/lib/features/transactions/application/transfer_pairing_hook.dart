// T-233: offers every transfer leg the ingest stores to transfer pairing
// (T-089), inside the message's savepoint (PostPersistHook). Before this hook
// a transfer between two of the user's own accounts that arrived by SMS was
// never paired: the out leg counted as spend and the in leg as income.
// `onPersisted` is idempotent and ignores rows that are not posted transfer
// legs. A pairing failure never costs the transaction (the next trigger, an
// edit or a late message, tries again).

import '../../ingestion/domain/ingest_ports.dart';
import 'transfer_pairing.dart';

final class TransferPairingHook implements PostPersistHook {
  TransferPairingHook(this._pairing);

  final TransferPairingUseCase _pairing;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    try {
      await _pairing.onPersisted(txn.txnId);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
