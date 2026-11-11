// T-008: fakes for the ingestion cycle. Bodies are synthetic.

import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/raw_message_mapper.dart';
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
  String? drainFails;
  String? ackFails;

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
}

base class FakeStore implements IngestStore {
  FakeStore(this.log);

  final List<String> log;
  bool exists = true;
  String? openFails;
  bool commitFails = false;
  int opens = 0;
  final List<StoreRow> committed = [];

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

  @override
  Future<int> commit(List<StoreRow> rows) async {
    log.add('commit');
    if (commitFails) throw StateError('DB_WRITE_FAILED');
    committed.addAll(rows);
    return rows.length;
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
