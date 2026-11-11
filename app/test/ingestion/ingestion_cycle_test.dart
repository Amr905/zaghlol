// T-008 design note §9 (Dart unit): the ingestionMain controller with fakes.
// T-046: order drain → ingest (parse + one transaction) → ack; a failed
// batch → no ack; stuck entries; migration pending → no ack, deferred;
// missing DB → no open, no ack.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';

import 'ingestion_fakes.dart';

void main() {
  late List<String> log;
  late FakeSpool spool;
  late FakeStore store;

  IngestionCycle cycle({
    int batch = 20,
    bool mayCreate = false,
    int Function()? nowMs,
  }) => IngestionCycle(
    spool: spool,
    store: store,
    mayCreateDatabase: mayCreate,
    marks: RecordingMarks(log),
    batchSize: batch,
    nowMs: nowMs,
  );

  setUp(() {
    log = [];
    spool = FakeSpool([
      entry(sid(1)),
      entry(sid(2), body: 'spike: something else'),
    ], log);
    store = FakeStore(log);
  });

  test('order: drain → ingest → ack, ack only after the use case '
      'returned', () async {
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.ok);
    expect(r.drained, 2);
    expect(r.inserted, 2);
    expect(log, [
      'exists',
      'open',
      'mark:db_open',
      'drain',
      'ingest',
      'mark:commit:2',
      'ack',
      'drain',
    ]);
    expect(spool.acked, [
      [sid(1), sid(2)],
    ]);
    expect(store.committed.map((m) => m.origin.name), ['spool', 'spool']);
  });

  for (final code in ['DB_WRITE_FAILED', 'DB_READ_FAILED']) {
    test('a transient batch failure ($code) → nothing acked, retry', () async {
      store.ingestFails = code;
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.retry);
      expect(r.code, code);
      expect(spool.acked, isEmpty);
      expect(log, isNot(contains('ack')));
    });
  }

  test('a non-transient batch failure → nothing acked; the re-drained '
      'entries are stuck, the cycle ends OK with a stuck count', () async {
    store.ingestFails = 'INGEST_MSG_UNSTORABLE';
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.ok);
    expect(r.stuck, 2);
    expect(r.code, 'INGEST_MSG_UNSTORABLE');
    expect(r.toWire()['stuck'], 2);
    expect(spool.acked, isEmpty);
    expect(spool.pending, hasLength(2), reason: 'never deleted');
    expect(log.where((l) => l == 'ingest'), hasLength(1));
  });

  test('CONFIG_INVALID (bad Guard base) acks nothing and keeps the '
      'spool', () async {
    store.ingestFails = 'CONFIG_INVALID';
    final r = await cycle().run();
    expect(r.code, 'CONFIG_INVALID');
    expect(spool.acked, isEmpty);
    expect(spool.pending, hasLength(2));
  });

  test('the next cycle after a stuck one processes the entries', () async {
    store
      ..ingestFails = 'INGEST_INTERNAL'
      ..failTimes = 1;
    expect((await cycle().run()).stuck, 2);
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.ok);
    expect(r.stuck, 0);
    expect(spool.pending, isEmpty);
  });

  test('no batch starts with under 5 s of the budget left', () async {
    var now = 0;
    spool.pending.addAll([for (var i = 3; i <= 9; i++) entry(sid(i))]);
    final r = await cycle(
      batch: 2,
      nowMs: () {
        final t = now;
        now += 30000; // each look at the clock "takes" 30 s
        return t;
      },
    ).run();
    // start 0; at 30 s one batch runs (< 45 s); at 60 s none starts.
    expect(r.outcome, CycleOutcome.ok);
    expect(spool.acked, hasLength(1));
    expect(spool.pending, isNotEmpty);
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

  test('dropped entries are acked, not counted as stored', () async {
    spool.pending
      ..clear()
      ..addAll([entry(sid(1), body: 'spike: your OTP is 1234'), entry(sid(2))]);
    final r = await cycle().run();
    expect(r.outcome, CycleOutcome.ok);
    expect(r.inserted, 1);
    expect(spool.acked.single, [sid(1), sid(2)]);
  });

  test('no result or wire map ever carries message text', () async {
    spool.pending
      ..clear()
      ..add(entry(sid(1), body: '$canary EGP 5'));
    for (final arrange in <void Function()>[
      () {},
      () => store.ingestFails = 'DB_WRITE_FAILED',
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
