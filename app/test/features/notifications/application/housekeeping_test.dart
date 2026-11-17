// FU-253: the follow-up jobs after ingest / at start. Fails without the
// orchestrator (nothing ran them) and without the restore-gate check.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/application/housekeeping.dart';
import 'package:zaghlol/features/notifications/application/housekeeping_providers.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/ingestion/ingestion_pause_gate.dart';

void main() {
  late int now;
  late List<String> calls;

  HousekeepingStep step(String n, {bool fail = false}) => (
    name: n,
    run: () async {
      calls.add(n);
      if (fail) throw StateError('x');
    },
  );

  setUp(() {
    now = 1000000;
    calls = [];
  });

  test(
    'runs every step in order; a failing step does not stop the rest',
    () async {
      final h = Housekeeping(
        steps: [step('a'), step('b', fail: true), step('c')],
        nowMs: () => now,
      );
      final r = await h.run();
      expect(calls, ['a', 'b', 'c']);
      expect(r.ran, ['a', 'c']);
      expect(r.failed, ['b']);
    },
  );

  test('throttled within the interval, forced or later runs again', () async {
    final h = Housekeeping(steps: [step('a')], nowMs: () => now);
    await h.run();
    now += 30000;
    expect((await h.run()).skipped, 'throttled');
    expect((await h.run(force: true)).ran, ['a']);
    now += 61000;
    expect((await h.run()).ran, ['a']);
    expect(calls, ['a', 'a', 'a']);
  });

  test('a second call during a run is dropped (single flight)', () async {
    final h = Housekeeping(steps: [step('a')], nowMs: () => now);
    final first = h.run();
    final second = await h.run(force: true);
    expect(second.skipped, 'busy');
    await first;
    expect(calls, ['a']);
  });

  test('nothing runs while the restore gate is closed', () async {
    final gate = IngestionPauseGate();
    final h = Housekeeping(steps: [step('a')], nowMs: () => now, gate: gate);
    await gate.pause();
    expect((await h.run(force: true)).skipped, 'paused');
    expect(calls, isEmpty);
    gate.resume();
    expect((await h.run(force: true)).ran, ['a']);
  });

  test('a restore starting mid-run stops before the next step', () async {
    final gate = IngestionPauseGate();
    final h = Housekeeping(
      gate: gate,
      nowMs: () => now,
      steps: [
        (
          name: 'a',
          run: () async {
            calls.add('a');
            // Pause is requested while this step is the one in flight.
            final p = gate.pause();
            await Future<void>.delayed(Duration.zero);
            expect(gate.paused, isTrue);
            // The step finishes; pause completes after it.
            addTearDown(() => p);
          },
        ),
        step('b'),
      ],
    );
    final r = await h.run(force: true);
    expect(calls, ['a']);
    expect(r.ran, ['a']);
  });

  test(
    'afterIngestProvider: duplicate check, then the follow-up jobs',
    () async {
      final order = <String>[];
      final h = Housekeeping(
        steps: [(name: 'x', run: () async => order.add('jobs'))],
        nowMs: () => now,
      );
      final c = ProviderContainer(
        overrides: [
          duplicateCheckProvider.overrideWithValue(
            () async => order.add('dup'),
          ),
          housekeepingProvider.overrideWithValue(h),
        ],
      );
      addTearDown(c.dispose);
      await c.read(afterIngestProvider)();
      expect(order, ['dup', 'jobs']);
    },
  );
}
