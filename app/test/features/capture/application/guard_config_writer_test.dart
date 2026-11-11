// T-047 test plan 1-3: the Guard config writer. Fake host and scheduler.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardIgnoreRuleInput, buildGuardUserConfig;

import '../support/capture_fakes.dart';

void main() {
  late FakeHost host;
  late FakeInputs inputs;
  late FakeScheduler sched;
  late GuardConfigWriter writer;

  setUp(() {
    host = FakeHost();
    inputs = FakeInputs();
    sched = FakeScheduler();
    writer = GuardConfigWriter(
      host: host,
      inputs: inputs,
      baseRegistryVersion: 3,
      scheduler: sched,
    );
  });
  tearDown(() => writer.dispose());

  String decoded(List<int> bytes) => utf8.decode(bytes);

  group('1. rewrite before the next capture', () {
    test('a rule added then `await flush()`: the fake host has the new '
        'bytes before flush completed', () async {
      inputs.set(rules: [ruleNbe4567]);
      final result = await writer.flush();
      expect(result.ok, isTrue);
      expect(host.writes, 1);
      expect(decoded(host.nativeBytes!), contains('nbe'));
    });

    test('a change during an in-flight write gives exactly one more write '
        'and flush waits for it', () async {
      host.writeGate = Completer<void>();
      final first = writer.flush();
      await pumpEventQueue();
      expect(host.writes, 1);
      // The rule arrives while the first write is in flight.
      inputs.set(rules: [ruleNbe4567]);
      var secondDone = false;
      final second = writer.flush().then((r) {
        secondDone = true;
        return r;
      });
      final third = writer.flush();
      await pumpEventQueue();
      expect(secondDone, isFalse, reason: 'must wait for a later write');
      final gate = host.writeGate!;
      host.writeGate = null;
      gate.complete();
      await Future.wait([first, second, third]);
      expect(host.writes, 2, reason: 'one more write, shared by both waiters');
      expect(decoded(host.nativeBytes!), contains('nbe'));
      expect(host.writeCopies.first, isNot(equals(host.writeCopies.last)));
    });

    test('table changes are written 300 ms after the last one', () async {
      writer.onInputsChanged();
      writer.onInputsChanged();
      expect(sched.live, hasLength(1), reason: 'trailing debounce');
      expect(sched.liveDelays.single, kGuardDebounce);
      expect(writer.dirty, isTrue);
      sched.fire(kGuardDebounce);
      await pumpEventQueue();
      expect(host.writes, 1);
      expect(writer.dirty, isFalse);
    });

    test('flush has no debounce and cancels a pending one', () async {
      writer.onInputsChanged();
      await writer.flush();
      expect(host.writes, 1);
      expect(sched.live, isEmpty);
    });
  });

  group('2. L-2: the user part is never kept', () {
    test('the buffer handed to native is all zero after the call', () async {
      inputs.set(rules: [ruleNbe4567], always: [senderMyBank]);
      await writer.flush();
      final sent = host.writeCopies.single;
      expect(sent.any((b) => b != 0), isTrue, reason: 'bytes were real');
      for (final buffer in host.writeBuffers) {
        expect(buffer.every((b) => b == 0), isTrue);
      }
    });

    test('also zeroed when native fails', () async {
      inputs.set(rules: [ruleNbe4567]);
      host.writeFails = 'IO_ERROR';
      await writer.flush();
      expect(host.writeBuffers.single.every((b) => b == 0), isTrue);
    });

    test('status and results carry codes only (sentinel scan)', () async {
      inputs.set(
        rules: [
          const GuardIgnoreRuleInput(
            institutionCode: 'nbe',
            last4: 'SENTINEL_BAD',
            channel: 'sms',
          ),
        ],
        always: [senderMyBank],
      );
      final r = await writer.flush();
      final dump = '${r.status} ${writer.status} $r ${writer.status.path}';
      for (final secret in ['nbe', 'SENTINEL_BAD', 'mybank', '4567']) {
        expect(dump, isNot(contains(secret)));
      }
      expect(writer.status.path, r'$.ignore[0].last4');
    });

    test('the writer state is an enum and codes (no bytes in it)', () async {
      inputs.set(rules: [ruleNbe4567]);
      await writer.flush();
      // The writer's own state: an enum and codes. toString of the writer
      // objects holds nothing.
      expect(writer.status.toString(), isNot(contains('nbe')));
      expect(writer.status.state, GuardWriteState.written);
    });
  });

  group('3. failure table', () {
    test('builder error: buildFailed(code, path), no native call, the old '
        'bytes stay, no retry', () async {
      inputs.set(rules: [ruleNbe4567]);
      await writer.flush();
      final before = List<int>.of(host.nativeBytes!);
      inputs.set(
        rules: [
          const GuardIgnoreRuleInput(
            institutionCode: 'BAD CODE',
            last4: null,
            channel: 'sms',
          ),
        ],
      );
      final r = await writer.flush();
      expect(r.status.state, GuardWriteState.buildFailed);
      expect(r.status.code, 'badValue');
      expect(r.status.path, r'$.ignore[0].inst');
      expect(host.writes, 1, reason: 'no native call');
      expect(host.nativeBytes, before);
      expect(sched.live, isEmpty);
    });

    test('CONFIG_INVALID is rejected and never retried', () async {
      host.writeFails = 'CONFIG_INVALID';
      final r = await writer.flush();
      expect(r.status.state, GuardWriteState.rejected);
      expect(sched.live, isEmpty);
      expect(host.nativeBytes, isNull);
    });

    test('IO_ERROR retries after 2 s, 10 s, 60 s, then is parked', () async {
      host.writeFails = 'IO_ERROR';
      final r = await writer.flush();
      expect(r.status.state, GuardWriteState.transient);
      expect(sched.liveDelays, [const Duration(seconds: 2)]);
      sched.fire(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(sched.liveDelays, [const Duration(seconds: 10)]);
      sched.fire(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(sched.liveDelays, [const Duration(seconds: 60)]);
      sched.fire(const Duration(seconds: 60));
      await pumpEventQueue();
      expect(sched.live, isEmpty);
      expect(writer.status.state, GuardWriteState.parked);
      expect(host.writes, 4);
      expect(host.nativeBytes, isNull, reason: 'old file never replaced');
    });

    test('a retry that succeeds clears the failure', () async {
      host.writeFails = 'IO_ERROR';
      await writer.flush();
      host.writeFails = null;
      sched.fire(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(writer.status.state, GuardWriteState.written);
      expect(sched.live, isEmpty);
    });

    test('PLATFORM_* codes are transient too', () async {
      host.writeFails = 'UNKNOWN';
      final r = await writer.flush();
      expect(r.status.state, GuardWriteState.transient);
    });

    test('NOT_AVAILABLE is unavailable, no retry', () async {
      host.writeFails = 'NOT_AVAILABLE';
      final r = await writer.flush();
      expect(r.status.state, GuardWriteState.unavailable);
      expect(sched.live, isEmpty);
    });

    test('a new trigger resets the retry schedule', () async {
      host.writeFails = 'IO_ERROR';
      await writer.flush();
      sched.fire(const Duration(seconds: 2));
      await pumpEventQueue();
      host.writeFails = null;
      final r = await writer.flush();
      expect(r.ok, isTrue);
      expect(sched.live, isEmpty);
    });

    test('flush never throws, also when the DB read fails', () async {
      final bad = GuardConfigWriter(
        host: host,
        inputs: _ThrowingInputs(),
        baseRegistryVersion: 1,
        scheduler: sched,
      );
      final r = await bad.flush();
      expect(r.status.state, GuardWriteState.transient);
      expect(host.writes, 0);
      bad.dispose();
    });
  });

  group('trigger (d): verify after a rewrite', () {
    test('full after the write: one write', () async {
      final r = await writer.flushAndVerify(() async => GuardFileState.full);
      expect(r.ok, isTrue);
      expect(host.writes, 1);
    });

    test('not full: one retry, then notEffective', () async {
      final r = await writer.flushAndVerify(
        () async => GuardFileState.userUnreadable,
      );
      expect(host.writes, 2);
      expect(r.status.state, GuardWriteState.notEffective);
      expect(writer.status.state, GuardWriteState.notEffective);
    });

    test('full on the retry: ok', () async {
      var n = 0;
      final r = await writer.flushAndVerify(
        () async => n++ == 0 ? GuardFileState.baseOnly : GuardFileState.full,
      );
      expect(host.writes, 2);
      expect(r.ok, isTrue);
    });
  });
}

class _ThrowingInputs extends FakeInputs {
  @override
  Future<Never> read() async => throw StateError('x');
}
