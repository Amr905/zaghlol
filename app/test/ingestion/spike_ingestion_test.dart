// T-008: cycles are serialised per engine; a request during a run schedules
// exactly one more run. The foreground spike starts only in devSms.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/ingestion_main.dart';
import 'package:zaghlol/ingestion/spike_foreground.dart';
import 'package:zaghlol/ingestion/spike_ingestion.dart';

import 'ingestion_fakes.dart';

final class GatedStore extends FakeStore {
  GatedStore(super.log);

  Completer<void>? gate;

  @override
  Future<bool> databaseExists() async {
    await gate?.future;
    return super.databaseExists();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a drain during a run joins it and triggers one more run', () async {
    final log = <String>[];
    final store = GatedStore(log)..gate = Completer<void>();
    final ingestion = SpikeIngestion(
      marks: RecordingMarks(log),
      headless: true,
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
    late SpikeIngestion ingestion;
    Completer<void>? nextGate;

    setUp(() {
      log = <String>[];
      builds = 0;
      nextGate = null;
      spool = FakeSpool([entry(sid(1))], log);
      ingestion = SpikeIngestion(
        marks: const NoMarks(),
        headless: true,
        spool: spool,
        store: (_, _) {
          builds++;
          return store = GatedStore(log)..gate = nextGate;
        },
        dbDirectory: () async => Directory.systemTemp,
      );
    });

    test('UI engine attaches mid-drain: close waits for the running cycle '
        '(commit and ack first), then closes the store', () async {
      final gate = nextGate = Completer<void>();
      final drain = ingestion.drain();
      await pumpEventQueue();
      expect(builds, 1, reason: 'the cycle started');
      expect(log, isEmpty, reason: 'and is held mid-run');
      final closed = handleSpikeCommand(ingestion, 'close');
      await pumpEventQueue();
      expect(log, isNot(contains('close')), reason: 'cycle still running');
      gate.complete();
      final r = await drain;
      expect(await closed, {'result': 'CLOSED'});
      expect(r.outcome, CycleOutcome.ok);
      expect(spool.pending, isEmpty);
      expect(log.indexOf('ack'), lessThan(log.indexOf('close')));
      expect(log.last, 'close');
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

    test('close without any drain is a no-op that answers CLOSED', () async {
      expect(await handleSpikeCommand(ingestion, 'close'), {
        'result': 'CLOSED',
      });
      expect(builds, 0);
      expect(await handleSpikeCommand(ingestion, 'other'), isNull);
    });
  });

  test('setup failure is a code-only retry', () async {
    final ingestion = SpikeIngestion(
      marks: const NoMarks(),
      headless: true,
      spool: FakeSpool([], []),
      dbDirectory: () async => throw StateError(canary),
    );
    final r = await ingestion.drain();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'INGEST_SETUP_FAILED');
  });

  test('foreground spike: off unless the flavour is devSms', () {
    expect(startSpikeForeground(flavor: null), isNull);
    expect(startSpikeForeground(flavor: 'devNoSms'), isNull);
    expect(startSpikeForeground(flavor: 'prodSms'), isNull);
    final started = startSpikeForeground(flavor: 'devSms');
    addTearDown(() => CaptureEventsApi.setUp(null));
    expect(started, isNotNull);
  });
}
