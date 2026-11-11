// T-008: fakes for the ingestion cycle. Bodies are synthetic.

import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spool_port.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

const String canary = 'ZG_CANARY_7731';

SpoolEntry entry(
  String id, {
  String body = 'spike: you paid EGP 12.50 at SYNTH SHOP card *4321',
  String source = '5550100',
  String channel = 'sms',
}) => SpoolEntry(
  id: id,
  channel: channel,
  source: source,
  body: body,
  receivedAtMs: 1700000000000,
  simSlot: 0,
);

/// Spool ids look like ULIDs: 26 Crockford characters.
String sid(int n) => '01JA${n.toString().padLeft(22, '0')}';

final class FakeSpool implements SpoolPort {
  FakeSpool(this.pending, this.log);

  final List<SpoolEntry> pending;
  final List<String> log;
  final List<List<String>> acked = [];
  final List<List<String>> heldCalls = [];
  final List<SpoolEntry> held = [];
  String? drainFails;
  String? ackFails;
  String? holdFails;

  @override
  Future<List<SpoolEntry>> drain(int max) async {
    log.add('drain');
    if (drainFails != null) {
      throw SpoolPortException(PlatformFailure.fromChannel(drainFails));
    }
    return pending.take(max).toList();
  }

  @override
  Future<void> ack(List<String> ids) async {
    log.add('ack');
    if (ackFails != null) {
      throw SpoolPortException(PlatformFailure.fromChannel(ackFails));
    }
    acked.add(ids);
    pending.removeWhere((e) => ids.contains(e.id));
  }

  /// Like native: moves the entries out of the pending spool.
  @override
  Future<void> hold(List<String> ids) async {
    log.add('hold');
    heldCalls.add(ids);
    if (holdFails != null) {
      throw SpoolPortException(PlatformFailure.fromChannel(holdFails));
    }
    held.addAll(pending.where((e) => ids.contains(e.id)));
    pending.removeWhere((e) => ids.contains(e.id));
  }
}

base class FakeStore implements IngestStore {
  FakeStore(this.log);

  final List<String> log;
  bool exists = true;
  String? openFails;

  /// Throw IngestBatchFailed with this code from [ingest].
  String? ingestFails;

  /// Fail only this many calls, then succeed.
  int failTimes = 1 << 30;
  int opens = 0;
  final List<IncomingMessage> committed = [];

  /// Delivery ids the use case "could not store even alone" (kept: neither
  /// committed nor ackable, FU-105).
  final Set<String> unstorable = {};

  @override
  Future<bool> databaseExists() async {
    log.add('exists');
    return exists;
  }

  @override
  Future<void> open() async {
    log.add('open');
    opens++;
    if (openFails != null) throw IngestStoreUnavailable(openFails!);
  }

  /// Every message is "inserted" except bodies containing `OTP` (dropped).
  /// Called at the start of each [ingest] (tests set a stop flag here).
  void Function()? onIngest;

  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) async {
    log.add('ingest');
    onIngest?.call();
    if (ingestFails != null && failTimes > 0) {
      failTimes--;
      throw IngestBatchFailed(ingestFails!);
    }
    final outcomes = <String, IngestOutcome>{};
    final kept = <String>[];
    for (final m in batch) {
      if (unstorable.contains(m.deliveryId)) {
        kept.add(m.deliveryId);
      } else if (m.body.contains('OTP')) {
        outcomes[m.deliveryId] = const IngestDropped('otp_or_promo_global');
      } else {
        committed.add(m);
        outcomes[m.deliveryId] = IngestInserted('t-${m.deliveryId}');
      }
    }
    return IngestBatchResult(
      outcomes: outcomes,
      ackable: [
        for (final m in batch)
          if (!kept.contains(m.deliveryId)) m.deliveryId,
      ],
      kept: kept,
      changedTxnIds: const {},
      changedAccountIds: const {},
      createdAccountIds: const {},
    );
  }

  int closes = 0;

  @override
  Future<void> close() async {
    log.add('close');
    closes++;
  }
}

final class RecordingMarks implements CycleMarks {
  RecordingMarks(this.log);

  final List<String> log;

  @override
  void dbOpen() => log.add('mark:db_open');

  @override
  void mark(String stage, List<String> ids) =>
      log.add('mark:$stage:${ids.length}');
}
