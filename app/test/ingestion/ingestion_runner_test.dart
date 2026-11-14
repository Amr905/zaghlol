// T-041 (from the T-008 spike test): cycles are serialised per engine; a
// request during a run schedules exactly one more run; close stops after the
// current batch and awaits the DB close; the flavour constant picks the spike registry
// only in devSms.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingestion_config.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/ingestion_main.dart';
import 'package:zaghlol/ingestion/ingestion_runner.dart';
import 'package:zaghlol/ingestion/spike_channel.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';

import 'ingestion_fakes.dart';

final class GatedStore extends FakeStore {
  GatedStore(super.log);

  Completer<void>? gate;

  /// Holds the first batch inside the use case (mid-batch).
  Completer<void>? batchGate;

  @override
  Future<bool> databaseExists() async {
    await gate?.future;
    return super.databaseExists();
  }

  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) async {
    final g = batchGate;
    batchGate = null;
    await g?.future;
    return super.ingest(batch);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a drain during a run joins it and triggers one more run', () async {
    final log = <String>[];
    final store = GatedStore(log)..gate = Completer<void>();
    final ingestion = IngestionRunner(
      marks: RecordingMarks(log),
      headless: true,
      registry: loadSpikeRegistry,
      spool: FakeSpool([], log),
      store: (_, _) => store,
      dbDirectory: () async => Directory.systemTemp,
    );
    final first = ingestion.drain();
    final second = ingestion.drain();
    final third = ingestion.drain();
    store.gate!.complete();
    store.gate = null;
    final results = await Future.wait([first, second, third]);
    expect(results.every((r) => r.outcome == CycleOutcome.ok), isTrue);
    expect(log.where((l) => l == 'exists'), hasLength(2));
  });

  group('close (F1)', () {
    late List<String> log;
    late GatedStore store;
    late FakeSpool spool;
    late int builds;
    late IngestionRunner ingestion;
    Completer<void>? nextGate;
    Completer<void>? nextBatchGate;

    setUp(() {
      log = <String>[];
      builds = 0;
      nextGate = null;
      nextBatchGate = null;
      spool = FakeSpool([entry(sid(1))], log);
      ingestion = IngestionRunner(
        marks: const NoMarks(),
        headless: true,
        registry: loadSpikeRegistry,
        spool: spool,
        store: (_, _) {
          builds++;
          return store = GatedStore(log)
            ..gate = nextGate
            ..batchGate = nextBatchGate;
        },
        dbDirectory: () async => Directory.systemTemp,
      );
    });

    test('UI engine attaches mid-batch: close waits for the running batch '
        '(commit and ack first), then closes the store', () async {
      final batch = nextBatchGate = Completer<void>();
      final drain = ingestion.drain();
      await pumpEventQueue();
      expect(builds, 1, reason: 'the cycle started');
      expect(log.last, 'drain', reason: 'and is held mid-batch');
      final closed = HeadlessIngestionHandler(ingestion).close();
      await pumpEventQueue();
      expect(log, isNot(contains('close')), reason: 'batch still running');
      batch.complete();
      final r = await drain;
      await closed;
      expect(r.outcome, CycleOutcome.ok);
      expect(spool.pending, isEmpty);
      expect(log.indexOf('ack'), lessThan(log.indexOf('close')));
      expect(log.last, 'close');
      expect(store.closes, 1);
    });

    test('close before the first batch: no batch starts, the spool is kept '
        'for the next engine, the store is closed', () async {
      final gate = nextGate = Completer<void>();
      final drain = ingestion.drain();
      await pumpEventQueue();
      final closed = ingestion.close();
      gate.complete();
      final r = await drain;
      await closed;
      expect(r.outcome, CycleOutcome.ok);
      expect(r.drained, 0);
      expect(log, isNot(contains('drain')));
      expect(spool.pending, hasLength(1));
      expect(store.closes, 1);
    });

    test('a drain requested during close runs after it on a new store '
        '(reopens)', () async {
      expect((await ingestion.drain()).outcome, CycleOutcome.ok);
      final first = store;
      final closed = ingestion.close();
      spool.pending.add(entry(sid(2)));
      final again = ingestion.drain();
      await closed;
      expect(first.closes, 1);
      final r = await again;
      expect(r.outcome, CycleOutcome.ok);
      expect(r.drained, 1);
      expect(builds, 2, reason: 'the closed store is never reused');
      expect(identical(store, first), isFalse);
      expect(store.opens, 1);
      expect(spool.pending, isEmpty);
    });

    test('close without any drain is a no-op that answers', () async {
      await HeadlessIngestionHandler(ingestion).close();
      expect(builds, 0);
    });

    test('close mid-cycle stops after the current batch (T-041): a UI '
        'engine waits one batch, not a whole cycle', () async {
      spool.pending
        ..clear()
        ..addAll([for (var i = 1; i <= 50; i++) entry(sid(i))]);
      final batch = nextBatchGate = Completer<void>();
      final drain = ingestion.drain();
      await pumpEventQueue();
      final closed = ingestion.close();
      batch.complete();
      final r = await drain;
      await closed;
      expect(r.outcome, CycleOutcome.ok);
      expect(r.drained, kDrainBatchSize, reason: 'one batch, then stop');
      expect(spool.pending, hasLength(50 - kDrainBatchSize));
      expect(log.where((l) => l == 'drain'), hasLength(1));
      expect(log.last, 'close');
      expect(store.closes, 1);
    });

    test('a drain queued during a running cycle is skipped once close '
        'stops it, and runs after the close on a new store', () async {
      final batch = nextBatchGate = Completer<void>();
      final first = ingestion.drain();
      await pumpEventQueue();
      final joined = ingestion.drain(); // schedules "one more run"
      final closed = ingestion.close();
      batch.complete();
      await first;
      await joined;
      await closed;
      expect(builds, 1, reason: 'no extra run after the stop');
      spool.pending.add(entry(sid(9)));
      expect((await ingestion.drain()).drained, 1);
      expect(builds, 2);
    });
  });

  test('setup failure is a code-only retry', () async {
    final ingestion = IngestionRunner(
      marks: const NoMarks(),
      headless: true,
      registry: loadSpikeRegistry,
      spool: FakeSpool([], []),
      dbDirectory: () async => throw StateError(canary),
    );
    final r = await ingestion.drain();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'INGEST_SETUP_FAILED');
  });

  test('the flavour constant selects the spike registry and marks only in '
      'devSms (tests run without a flavour)', () {
    expect(kIsSpikeBuild, isFalse);
    expect(identical(defaultRegistryLoader, loadSpikeRegistry), isFalse);
    expect(defaultCycleMarks(), isA<NoMarks>());
    expect(defaultRegistryLoader, throwsStateError);
  });

  test('a registry that cannot load is a code-only setup failure', () async {
    final r = await IngestionRunner(
      marks: const NoMarks(),
      headless: true,
      spool: FakeSpool([entry(sid(1))], []),
      store: (_, _) => FakeStore([]),
      dbDirectory: () async => Directory.systemTemp,
      registry: () => throw StateError('INGEST_REGISTRY_MISSING'),
    ).drain();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'INGEST_SETUP_FAILED');
  });
}
