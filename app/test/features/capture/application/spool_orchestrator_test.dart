// T-047 test plan 7: the UI engine's drain orchestration.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/application/spool_orchestrator.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';

import '../support/capture_fakes.dart';

void main() {
  late FakeHost host;
  late FakeScheduler sched;
  late List<CycleResult> script;
  late int cycles;
  Completer<void>? gate;
  late int tablesUpdated;
  late SpoolOrchestrator orchestrator;

  CycleResult ok({int drained = 0, int stuck = 0}) =>
      CycleResult(CycleOutcome.ok, drained: drained, stuck: stuck);

  setUp(() {
    host = FakeHost();
    sched = FakeScheduler();
    script = [];
    cycles = 0;
    gate = null;
    tablesUpdated = 0;
    orchestrator = SpoolOrchestrator(
      drain: () async {
        cycles++;
        final g = gate;
        if (g != null) await g.future;
        return script.isEmpty ? ok() : script.removeAt(0);
      },
      host: host,
      scheduler: sched,
      onTablesUpdated: () => tablesUpdated++,
    );
  });
  tearDown(() => orchestrator.dispose());

  test('onSpoolChanged is coalesced for 250 ms, then drains once', () async {
    orchestrator.onSpoolChanged();
    orchestrator.onSpoolChanged();
    orchestrator.onSpoolChanged();
    expect(sched.liveDelays, [kSpoolChangedCoalesce]);
    expect(cycles, 0);
    sched.fire(kSpoolChangedCoalesce);
    await pumpEventQueue();
    expect(cycles, 1);
  });

  test(
    'onSpoolChanged while a cycle runs gives exactly one extra cycle',
    () async {
      gate = Completer<void>();
      final first = orchestrator.drainNow();
      await pumpEventQueue();
      expect(cycles, 1);
      orchestrator.onSpoolChanged();
      sched.fire(kSpoolChangedCoalesce);
      orchestrator.onSpoolChanged();
      sched.fire(kSpoolChangedCoalesce);
      await pumpEventQueue();
      expect(cycles, 1, reason: 'serialised');
      final g = gate!;
      gate = null;
      g.complete();
      await first;
      expect(cycles, 2, reason: 'one more, not one per event');
    },
  );

  test('empty drain while pending > 0 re-polls at 5/15/45 s, then leaves '
      'it to the worker', () async {
    host.status = spoolStatus(pending: 3);
    await orchestrator.drainNow();
    expect(sched.liveDelays, [const Duration(seconds: 5)]);
    sched.fire(const Duration(seconds: 5));
    await pumpEventQueue();
    expect(sched.liveDelays, [const Duration(seconds: 15)]);
    sched.fire(const Duration(seconds: 15));
    await pumpEventQueue();
    expect(sched.liveDelays, [const Duration(seconds: 45)]);
    sched.fire(const Duration(seconds: 45));
    await pumpEventQueue();
    expect(sched.live, isEmpty, reason: 'no fourth poll');
    expect(host.scheduleNowCalls, 1);
    expect(cycles, 4);
  });

  test('no polling when nothing is pending', () async {
    host.status = spoolStatus(pending: 0);
    await orchestrator.drainNow();
    expect(sched.live, isEmpty);
    expect(host.scheduleNowCalls, 0);
  });

  test('a non-empty drain does not poll', () async {
    script = [ok(drained: 2)];
    host.status = spoolStatus(pending: 3);
    await orchestrator.drainNow();
    expect(sched.live, isEmpty);
    expect(tablesUpdated, 1);
  });

  test(
    'retry outcome: 5 s, 30 s, 2 min, then parked until a trigger',
    () async {
      CycleResult retry() =>
          const CycleResult(CycleOutcome.retry, code: 'DB_BUSY');
      script = [retry(), retry(), retry(), retry()];
      await orchestrator.drainNow();
      expect(sched.liveDelays, [const Duration(seconds: 5)]);
      sched.fire(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(sched.liveDelays, [const Duration(seconds: 30)]);
      sched.fire(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(sched.liveDelays, [const Duration(minutes: 2)]);
      sched.fire(const Duration(minutes: 2));
      await pumpEventQueue();
      expect(sched.live, isEmpty, reason: 'parked');
      expect(cycles, 4);
      // A trigger runs again and resets the schedule.
      script = [retry()];
      await orchestrator.onResumed();
      expect(sched.liveDelays, [const Duration(seconds: 5)]);
    },
  );

  test('deferred and noDatabase wait for a trigger (no timer)', () async {
    script = [const CycleResult(CycleOutcome.deferred, code: 'DB_DEFERRED')];
    await orchestrator.drainNow();
    expect(sched.live, isEmpty);
    script = [const CycleResult(CycleOutcome.noDatabase)];
    await orchestrator.drainNow();
    expect(sched.live, isEmpty);
  });

  test('ok with stuck entries is not retried', () async {
    script = [ok(drained: 1, stuck: 1)];
    await orchestrator.drainNow();
    expect(sched.live, isEmpty);
    expect(cycles, 1);
  });

  test(
    'resume marks the tables updated even when nothing was drained',
    () async {
      await orchestrator.onResumed();
      expect(tablesUpdated, 1);
    },
  );

  test('a throwing drain is a retry, never an escaped error', () async {
    final o = SpoolOrchestrator(
      drain: () async => throw StateError('x'),
      host: host,
      scheduler: sched,
    );
    await o.drainNow();
    expect(o.lastResult!.outcome, CycleOutcome.retry);
    o.dispose();
  });

  test('after dispose nothing runs', () async {
    orchestrator.dispose();
    await orchestrator.drainNow();
    orchestrator.onSpoolChanged();
    expect(cycles, 0);
    expect(sched.live, isEmpty);
  });

  test('the headless engine never reads the status or clears alerts (its '
      'entry file imports none of the capture module or those host calls)', () {
    final text = File('lib/ingestion/ingestion_main.dart').readAsStringSync();
    final cycle = File('lib/ingestion/ingestion_cycle.dart').readAsStringSync();
    final runner = File('lib/ingestion/ingestion_runner.dart')
        .readAsStringSync();
    for (final source in [text, cycle, runner]) {
      expect(source, isNot(contains('getSpoolStatus')));
      expect(source, isNot(contains('clearSpoolAlerts')));
      expect(source, isNot(contains('features/capture')));
      expect(source, isNot(contains('writeGuardConfig')));
    }
  });
}
