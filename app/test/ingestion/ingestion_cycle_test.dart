// T-008 design note §9 (Dart unit): the ingestionMain controller with fakes.
// Order drain → parse → commit → ack; commit throws → no ack; migration
// pending → no ack, deferred; missing DB → no open, no ack.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'ingestion_fakes.dart';

void main() {
  late List<String> log;
  late FakeSpool spool;
  late FakeStore store;

  IngestionCycle cycle({
    EntryParser? parse,
    int batch = 20,
    bool mayCreate = false,
  }) => IngestionCycle(
    spool: spool,
    store: store,
    parse:
        parse ??
        (e) {
          log.add('parse');
          return pipelineParser(ParsingPipeline(loadSpikeRegistry()))(e);
        },
    registryVersion: 1,
    mayCreateDatabase: mayCreate,
    marks: RecordingMarks(log),
    batchSize: batch,
  );

  setUp(() {
    log = [];
    spool = FakeSpool([
      entry(sid(1)),
      entry(sid(2), body: 'spike: something else'),
    ], log);
    store = FakeStore(log);
  });

  test(
    'order: drain → parse → commit → ack, ack only after the commit',
    () async {
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.ok);
      expect(r.drained, 2);
      expect(r.inserted, 2);
      expect(log, [
        'exists',
        'open',
        'mark:db_open',
        'drain',
        'parse',
        'parse',
        'mark:parsed:2',
        'commit',
        'mark:commit:2',
        'ack',
        'drain',
      ]);
      expect(spool.acked, [
        [sid(1), sid(2)],
      ]);
      expect(store.committed.map((r) => r.parsed), [true, false]);
      expect(store.committed.first.row.parseStatus.value, 'parsed');
      expect(store.committed.last.row.parseStatus.value, 'review');
    },
  );

  test('commit throws → nothing acked, retry', () async {
    store.commitFails = true;
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'DB_WRITE_FAILED');
    expect(spool.acked, isEmpty);
    expect(log, isNot(contains('ack')));
  });

  for (final (code, outcome) in [
    ('DB_MIGRATION_PENDING', CycleOutcome.deferred),
    ('DB_DEFERRED', CycleOutcome.deferred),
    ('DB_SCHEMA_TOO_NEW', CycleOutcome.deferred),
    ('DB_UNAVAILABLE', CycleOutcome.retry),
    ('DB_STORE_FAILED', CycleOutcome.retry),
  ]) {
    test('open fails with $code → ${outcome.wire}, no drain, no ack', () async {
      store.openFails = code;
      final r = await cycle().run();
      expect(r.outcome, outcome);
      expect(r.code, code);
      expect(log, ['exists', 'open']);
    });
  }

  test(
    'missing database → NO_DATABASE: never opened, spool untouched',
    () async {
      store.exists = false;
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.noDatabase);
      expect(r.toWire()['result'], 'NO_DATABASE');
      expect(store.opens, 0);
      expect(log, ['exists']);
      expect(spool.pending, hasLength(2));
    },
  );

  test('UI engine (may create): a missing database is opened, which '
      'creates it', () async {
    store.exists = false;
    final r = await cycle(mayCreate: true).run();
    expect(r.outcome, CycleOutcome.ok);
    expect(store.opens, 1);
    expect(log.take(2), ['open', 'mark:db_open']);
  });

  test('ack fails after the commit → retry (re-delivery is deduped)', () async {
    spool.ackFails = 'IO_ERROR';
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'PLATFORM_IO_ERROR');
    expect(store.committed, hasLength(2));
  });

  test('drain fails → retry; a non-code error code becomes UNKNOWN', () async {
    spool.drainFails = '$canary leaked text';
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'PLATFORM_UNKNOWN');
  });

  test('batches until the spool is empty', () async {
    spool.pending.addAll([
      for (var i = 3; i <= 7; i++) entry(sid(i), body: 'b$i'),
    ]);
    final r = await cycle(batch: 3).run();
    expect(r.drained, 7);
    expect(spool.acked.map((a) => a.length), [3, 3, 1]);
    expect(spool.pending, isEmpty);
  });

  test('a parser crash stores the row for review and still acks', () async {
    final r = await cycle(parse: (_) => throw StateError(canary)).run();
    expect(r.outcome, CycleOutcome.ok);
    expect(store.committed.map((r) => r.row.parseStatus.value), [
      'review',
      'review',
    ]);
    expect(spool.acked.single, hasLength(2));
  });

  test(
    'dropped (OTP) and unknown-channel entries are acked, not stored',
    () async {
      spool.pending
        ..clear()
        ..addAll([
          entry(sid(1), body: 'spike: your OTP is 1234'),
          entry(sid(2), channel: 'carrier_pigeon'),
        ]);
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.ok);
      expect(store.committed, isEmpty);
      expect(spool.acked.single, [sid(1), sid(2)]);
    },
  );

  test('no result or wire map ever carries message text', () async {
    spool.pending
      ..clear()
      ..add(entry(sid(1), body: '$canary EGP 5'));
    for (final arrange in <void Function()>[
      () {},
      () => store.commitFails = true,
      () => spool.ackFails = canary,
      () => store.openFails = 'DB_UNAVAILABLE',
    ]) {
      arrange();
      final r = await cycle().run();
      expect('${r.toWire()}', isNot(contains(canary)));
      expect('${r.code}', isNot(contains(canary)));
    }
  });
}
