// FU-253: the follow-up jobs after ingest / at start. Fails without the
// orchestrator (nothing ran them) and without the restore-gate check.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
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

  group('FU-255', () {
    test('a throttled call gets one trailing run at the window end', () async {
      final fired = <void Function()>[];
      final delays = <Duration>[];
      final h = Housekeeping(
        steps: [step('a')],
        nowMs: () => now,
        schedule: (d, f) {
          delays.add(d);
          fired.add(f);
          return Timer(const Duration(days: 1), () {});
        },
      );
      await h.run();
      now += 20000;
      expect((await h.run()).skipped, 'throttled');
      expect((await h.run()).skipped, 'throttled'); // still one trailing
      expect(fired, hasLength(1));
      expect(delays.single, const Duration(seconds: 40));
      now += 40000;
      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['a', 'a']);
    });

    test('a call during a run also gets a trailing run', () async {
      final fired = <void Function()>[];
      final h = Housekeeping(
        steps: [step('a')],
        nowMs: () => now,
        schedule: (d, f) {
          fired.add(f);
          return Timer(const Duration(days: 1), () {});
        },
      );
      final first = h.run();
      expect((await h.run()).skipped, 'busy');
      await first;
      expect(fired, hasLength(1));
    });

    test('no trailing run when asked not to, or after dispose', () async {
      final fired = <void Function()>[];
      final h = Housekeeping(
        steps: [step('a')],
        nowMs: () => now,
        schedule: (d, f) {
          fired.add(f);
          return Timer(const Duration(days: 1), () {});
        },
      );
      await h.run();
      await h.run(trailing: false);
      expect(fired, isEmpty);
      h.dispose();
      await h.run(); // throttled, but disposed
      expect(fired, isEmpty);
    });

    test('a per-call interval throttles a resume for longer', () async {
      final h = Housekeeping(steps: [step('a')], nowMs: () => now);
      await h.run();
      now += 120000; // past 60 s, inside 5 min
      expect(
        (await h.run(
          interval: const Duration(minutes: 5),
          trailing: false,
        )).skipped,
        'throttled',
      );
    });

    test('resume is throttled; cold start is forced', () async {
      var runs = 0;
      final h = Housekeeping(
        steps: [(name: 'x', run: () async => runs++)],
        nowMs: () => now,
      );
      final c = ProviderContainer(
        overrides: [
          alertsResumeProvider.overrideWithValue(() async {}),
          housekeepingProvider.overrideWithValue(h),
        ],
      );
      addTearDown(c.dispose);
      final resume = c.read(resumeJobsProvider);
      await resume(coldStart: true);
      for (var i = 0; i < 5; i++) {
        now += 10000;
        await resume();
      }
      expect(runs, 1);
      now += resumeJobsInterval.inMilliseconds;
      await resume();
      expect(runs, 2);
      await resume(coldStart: true);
      expect(runs, 3);
    });

    test('a gate change does not build a second runner', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final first = c.read(housekeepingProvider);
      c.invalidate(ingestionPauseGateProvider);
      expect(identical(c.read(housekeepingProvider), first), isTrue);
    });
  });
}
