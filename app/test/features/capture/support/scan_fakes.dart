// T-048: fakes for the scan tests. All data is synthetic.

import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/scan.dart';
import 'package:zaghlol/features/capture/data/scan_sources.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';

RawInboxMessage row(
  int id,
  String address, {
  String body = 'ZBANK: Purchase EGP 10.00 at Synth Shop card *4321',
  int dateMs = 1800000000000,
}) => RawInboxMessage(
  address: address,
  body: body,
  dateMs: dateMs + id * 1000,
  simSlot: 0,
  providerId: '$id',
);

final class FakeSenders implements ScanSenderSource {
  FakeSenders(this.senders);
  List<ScanSender> senders;
  int reads = 0;
  @override
  Future<List<ScanSender>> read() async {
    reads++;
    return senders;
  }
}

/// A store that records batches and answers every message as inserted
/// (or as [outcome] says).
final class FakeIngestStore implements IngestStore {
  final List<List<IncomingMessage>> batches = [];
  int opens = 0;
  Object? openFails;
  Object? Function(int call)? failOn;
  IngestOutcome Function(IncomingMessage m)? outcome;
  int calls = 0;

  List<IncomingMessage> get all => [for (final b in batches) ...b];

  @override
  Future<bool> databaseExists() async => true;

  @override
  Future<void> open() async {
    opens++;
    final f = openFails;
    if (f != null) throw f;
  }

  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) async {
    calls++;
    final e = failOn?.call(calls);
    if (e != null) throw e;
    batches.add(batch);
    return IngestBatchResult(
      outcomes: {
        for (final m in batch)
          m.deliveryId: outcome?.call(m) ?? IngestInserted('t${m.deliveryId}'),
      },
      ackable: [for (final m in batch) m.deliveryId],
      changedTxnIds: const {},
      changedAccountIds: const {},
      createdAccountIds: const {},
    );
  }

  @override
  Future<void> close() async {}
}

/// Adapts a real use case (integration tests).
final class UseCaseStore implements IngestStore {
  UseCaseStore(this._use);
  final IngestRawMessages _use;

  @override
  Future<bool> databaseExists() async => true;
  @override
  Future<void> open() async {}
  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) => _use(batch);
  @override
  Future<void> close() async {}
}

final class FakeWatermark implements WatermarkSource {
  FakeWatermark(this.value);
  int? value;
  Object? fails;
  @override
  Future<int?> maxSmsReceivedAtMs() async {
    if (fails != null) throw fails!;
    return value;
  }
}

/// An inbox served in pages by `_id` order, filtering by the query's
/// addresses and since like native does.
Future<InboxPage> Function(InboxQuery) inboxOf(
  List<RawInboxMessage> rows, {
  List<InboxQuery>? seen,
}) => (q) async {
  seen?.add(q);
  final want = {for (final a in q.senderAddresses) a.toLowerCase()};
  final after = q.afterCursor == null ? 0 : int.parse(q.afterCursor!);
  final matching = [
    for (final r in rows)
      if (want.contains(r.address.toLowerCase()) &&
          r.dateMs > q.sinceEpochMs &&
          int.parse(r.providerId) > after)
        r,
  ]..sort((a, b) => int.parse(a.providerId).compareTo(int.parse(b.providerId)));
  final page = matching.take(q.pageSize).toList();
  final more = matching.length > page.length;
  return InboxPage(
    items: page,
    nextCursor: more ? page.last.providerId : null,
    scannedTotal: page.length,
  );
};
