// T-047 test plan 5-7 at the coordinator level: start order, absorb-then-
// clear, keyInvalidated / userUnreadable rewrite, resume, hooks.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/capture_coordinator.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/data/catch_up_scheduler.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';

import '../support/capture_fakes.dart';

void main() {
  late FakeHost host;
  late FakeInputs inputs;
  late FakeScheduler sched;
  late MemoryAlertStore store;
  late RecordingCatchUpScheduler catchUp;
  late List<String> events;
  late int cycles;
  late CaptureCoordinator c;

  CaptureCoordinator make({CaptureHooks? hooks}) {
    final writer = GuardConfigWriter(
      host: host,
      inputs: inputs,
      baseRegistryVersion: 1,
      scheduler: sched,
    );
    return CaptureCoordinator(
      host: host,
      writer: writer,
      alerts: store,
      drain: () async {
        cycles++;
        host.log.add('drain');
        return const CycleResult(CycleOutcome.ok);
      },
      scheduler: sched,
      catchUp: catchUp,
      nowMs: () => 1700000000000,
      hooks:
          hooks ??
          CaptureHooks(
            attachShareIntake: () => events.add('attach'),
            pollShareIntake: () async => events.add('poll'),
            purgeExpired: () async => events.add('purge'),
          ),
    );
  }

  setUp(() {
    host = FakeHost();
    inputs = FakeInputs();
    sched = FakeScheduler();
    store = MemoryAlertStore();
    catchUp = RecordingCatchUpScheduler();
    events = [];
    cycles = 0;
    c = make();
  });
  tearDown(() => c.dispose());

  test('start order: capabilities, status read, config write (also with '
      'zero rows), drain, status read; share hooks and one purge', () async {
    await c.start();
    expect(host.log.take(4), ['status', 'write', 'drain', 'status']);
    expect(events, ['attach', 'poll', 'purge']);
    expect(host.writes, 1, reason: 'unconditional write');
    await c.start();
    expect(host.writes, 1, reason: 'start runs once');
  });

  test(
    'absorb-then-clear: the store is written before the clear call',
    () async {
      final order = host.log;
      final ordered = _OrderStore(store, order);
      final w = GuardConfigWriter(
        host: host,
        inputs: inputs,
        baseRegistryVersion: 1,
        scheduler: sched,
      );
      final cc = CaptureCoordinator(
        host: host,
        writer: w,
        alerts: ordered,
        drain: () async => const CycleResult(CycleOutcome.ok),
        scheduler: sched,
      );
      host.status = spoolStatus(seq: 11, missedNotifications: 3);
      await cc.start();
      expect(order.indexOf('store'), lessThan(order.indexOf('clear')));
      expect(host.clears, contains(11));
      expect(store.value.missedNotifications, 3);
      expect(store.value.absorbedSeq, 11);
      await cc.dispose();
    },
  );

  test('the same seq twice absorbs once; a failing clear then a good one '
      'does not double count', () async {
    host.status = spoolStatus(seq: 5, missedNotifications: 2);
    host.clearFails = 'IO_ERROR';
    await c.start();
    expect(store.value.missedNotifications, 2);
    expect(host.clears, isEmpty);
    host.clearFails = null;
    await c.orchestrator.drainNow();
    expect(store.value.missedNotifications, 2, reason: 'not added again');
    expect(host.clears, [5]);
    expect(store.writes, 1);
  });

  test(
    'missed notifications become an issue; dismiss zeroes the count only',
    () async {
      host.status = spoolStatus(seq: 5, missedNotifications: 2);
      await c.start();
      expect(c.health.issues, contains(CaptureIssue.missedNotifications));
      expect(c.health.missedNotifications, 2);
      await c.dismissMissedNotifications();
      expect(
        c.health.issues,
        isNot(contains(CaptureIssue.missedNotifications)),
      );
      expect(store.value.absorbedSeq, 5, reason: 'bookkeeping kept');
    },
  );

  test('keyInvalidatedAtMs alone: rewrite and a silent catch-up request, '
      'no notice (T-039 code 5)', () async {
    host.status = spoolStatus(seq: 99, keyInvalidatedAtMs: 1699999999999);
    // After a rewrite native reports the key state as fine again.
    host.onWrite = (h) => h.status = spoolStatus();
    await c.start();
    expect(store.value.catchUpReason, CatchUpReason.keyInvalidated);
    expect(store.value.catchUpFromMs, isNotNull);
    expect(c.health.issues, isNot(contains(CaptureIssue.unreadable)));
    expect(c.health.issues, isEmpty);
    expect(host.writes, 1, reason: 'one write, verified full');
    expect(host.clears, [99]);
    expect(catchUp.calls, greaterThan(0), reason: 'sms active: scan asked');
  });

  test('decryptDeleted > 0 raises the unreadable notice', () async {
    host.status = spoolStatus(seq: 4, decryptDeleted: 2);
    await c.start();
    expect(c.health.issues, contains(CaptureIssue.unreadable));
  });

  test('userUnreadable: written at once, re-read, expected full; still not '
      'full is notEffective after one retry', () async {
    host.status = spoolStatus(guardState: GuardConfigState.userUnreadable);
    await c.start();
    // start: unreadable -> write + verify (2 writes: retry), then drain; the
    // drain's status read does not repeat a rewrite that was not effective.
    expect(host.writes, 2);
    expect(c.health.issues, contains(CaptureIssue.guardWriteFailed));
    expect(c.health.issues, isNot(contains(CaptureIssue.unreadable)));
  });

  test(
    'userUnreadable that the rewrite fixes: one write, no problem',
    () async {
      host.status = spoolStatus(guardState: GuardConfigState.userUnreadable);
      host.onWrite = (h) => h.status = spoolStatus();
      await c.start();
      expect(host.writes, 1);
      expect(c.health.issues, isEmpty);
    },
  );

  test(
    'baseInvalid is a fault (no user action), unknown shows nothing',
    () async {
      host.status = spoolStatus(guardState: GuardConfigState.baseInvalid);
      await c.start();
      expect(c.health.mode, CaptureMode.fault);
      host.status = spoolStatus(guardState: GuardConfigState.unknown);
      await c.orchestrator.drainNow();
      expect(c.health.mode, CaptureMode.full);
      expect(c.health.issues, isEmpty);
    },
  );

  test('degraded mode comes from capabilities; a permission event updates '
      'the health and does not write', () async {
    await c.start();
    expect(c.health.mode, CaptureMode.full);
    final writes = host.writes;
    c.onPermissionChanged(
      CaptureCapabilities(
        smsGranted: false,
        smsFlavor: true,
        notificationAccess: true,
        postNotifications: true,
        sdkInt: 34,
      ),
    );
    expect(c.health.mode, CaptureMode.degraded);
    expect(c.health.issues, contains(CaptureIssue.smsOff));
    expect(host.writes, writes);
  });

  test('toggles: turning SMS off is not degraded', () async {
    await c.start();
    c.setToggles(const CaptureToggles(sms: false, notifications: true));
    expect(c.health.mode, CaptureMode.full);
    expect(c.health.channels[CaptureChannel.smsLive], ChannelState.offUser);
  });

  test(
    'catch-up is requested after a drain only while live SMS is active',
    () async {
      host.caps = CaptureCapabilities(
        smsGranted: false,
        smsFlavor: true,
        notificationAccess: true,
        postNotifications: true,
        sdkInt: 34,
      );
      await c.start();
      expect(catchUp.calls, 0);
    },
  );

  test('onSpoolChanged drains (the worker waits for it)', () async {
    await c.start();
    final before = cycles;
    c.onSpoolChanged(2);
    sched.fire(const Duration(milliseconds: 250));
    await pumpEventQueue();
    expect(cycles, before + 1);
  });

  test('resume: polls shares, reads status, drains; writes only when '
      'dirty or not full or key invalidated', () async {
    await c.start();
    final writes = host.writes;
    events.clear();
    await c.onResumed();
    expect(events, ['poll']);
    expect(host.writes, writes, reason: 'clean and full: no write');
    // Dirty:
    c.onGuardInputsChanged();
    await c.onResumed();
    expect(host.writes, writes + 1);
    // Not full:
    host.status = spoolStatus(guardState: GuardConfigState.baseOnly);
    host.onWrite = (h) => h.status = spoolStatus();
    await c.onResumed();
    expect(host.writes, writes + 2);
  });

  test('onRuleChanged: writes before it completes, then re-checks waiting '
      'entries with a drain', () async {
    await c.start();
    inputs.set(rules: [ruleNbe4567]);
    final before = cycles;
    final r = await c.onRuleChanged();
    expect(r.ok, isTrue);
    expect(String.fromCharCodes(host.nativeBytes!), contains('nbe'));
    await pumpEventQueue();
    expect(cycles, before + 1);
  });

  test('a failed hook of another module does not stop capture', () async {
    final cc = make(
      hooks: CaptureHooks(
        pollShareIntake: () async => throw StateError('x'),
        purgeExpired: () async => throw StateError('y'),
      ),
    );
    await cc.start();
    expect(host.writes, greaterThan(0));
    await cc.dispose();
  });
}

final class _OrderStore extends MemoryAlertStore {
  _OrderStore(this._inner, this._order);

  final MemoryAlertStore _inner;
  final List<String> _order;

  @override
  Future<void> write(PersistedAlerts next) async {
    _order.add('store');
    await _inner.write(next);
    value = next;
  }
}
