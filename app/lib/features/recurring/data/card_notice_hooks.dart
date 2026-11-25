// T-245: plugs the card dues into ingestion. The notice hook stores a due
// reminder or statement (never a transaction); the payment hook counts an
// inbound transfer on a card against its due. A payment-hook failure never
// costs the transaction (the due only misses one payment; nothing is marked
// paid on doubt).

import '../../ingestion/domain/ingest_ports.dart';
import 'card_dues.dart';

final class DriftCardNoticeHook implements CardNoticeHook {
  DriftCardNoticeHook(this._dues);

  final CardDues _dues;

  @override
  Future<void> onCardNotice(CardNoticeEvent event) =>
      _dues.onNotice(event, receivedAtMs: event.receivedAtMs);
}

final class CardDuePaymentHook implements PostPersistHook {
  CardDuePaymentHook(this._dues);

  final CardDues _dues;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    try {
      await _dues.onPayment(txn);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
