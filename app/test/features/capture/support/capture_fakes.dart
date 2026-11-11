// T-047: fakes for the capture module tests. All data is synthetic.

import 'dart:async';
import 'dart:typed_data';

import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/capture_scheduler.dart';
import 'package:zaghlol/features/capture/data/alert_store.dart';
import 'package:zaghlol/features/capture/data/capture_host_port.dart';
import 'package:zaghlol/features/capture/data/guard_inputs_reader.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardIgnoreRuleInput, GuardUserSenderInput;

SpoolStatus spoolStatus({
  int pending = 0,
  int seq = 0,
  int missedNotifications = 0,
  int? firstMissedSmsAtMs,
  int decryptDeleted = 0,
  int? keyInvalidatedAtMs,
  GuardConfigState guardState = GuardConfigState.full,
}) => SpoolStatus(
  pending: pending,
  seq: seq,
  refusedFull: 0,
  refusedGeneric: 0,
  rateLimited: 0,
  missedNotifications: missedNotifications,
  firstMissedSmsAtMs: firstMissedSmsAtMs,
  decryptDeleted: decryptDeleted,
  keyInvalidatedAtMs: keyInvalidatedAtMs,
  guardState: guardState,
  held: 0,
);

CaptureHostException hostError(String code) =>
    CaptureHostException(PlatformFailure.fromChannel(code));

final class FakeHost implements CaptureHostPort {
  FakeHost({CaptureCapabilities? caps})
    : caps =
          caps ??
          CaptureCapabilities(
            smsGranted: true,
            smsFlavor: true,
            notificationAccess: true,
            postNotifications: true,
            sdkInt: 34,
          );

  CaptureCapabilities caps;
  SpoolStatus status = spoolStatus();
  final List<String> log = [];

  /// The very buffers handed to writeGuardConfig (to prove they are zeroed).
  final List<Uint8List> writeBuffers = [];

  /// Copies taken during the call.
  final List<List<int>> writeCopies = [];
  String? writeFails;
  Completer<void>? writeGate;
  String? clearFails;
  final List<int> clears = [];
  int scheduleNowCalls = 0;
  Object? statusFails;

  /// Called after each successful write (native state transitions).
  void Function(FakeHost)? onWrite;

  /// The bytes native holds (the last successful write).
  List<int>? nativeBytes;

  int get writes => writeBuffers.length;

  @override
  Future<CaptureCapabilities> getCapabilities() async => caps;

  @override
  Future<void> writeGuardConfig(Uint8List userConfigJson) async {
    log.add('write');
    writeBuffers.add(userConfigJson);
    writeCopies.add(List<int>.of(userConfigJson));
    final gate = writeGate;
    if (gate != null) await gate.future;
    final fail = writeFails;
    if (fail != null) throw hostError(fail);
    nativeBytes = List<int>.of(userConfigJson);
    onWrite?.call(this);
  }

  @override
  Future<SpoolStatus> getSpoolStatus() async {
    log.add('status');
    if (statusFails != null) throw hostError('IO_ERROR');
    return status;
  }

  @override
  Future<void> clearSpoolAlerts(int seq) async {
    log.add('clear');
    if (clearFails != null) throw hostError(clearFails!);
    clears.add(seq);
  }

  @override
  Future<void> scheduleIngestionNow() async {
    log.add('scheduleNow');
    scheduleNowCalls++;
  }
}

final class FakeTimer {
  FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    _callback();
  }
}

final class FakeScheduler implements CaptureScheduler {
  final List<FakeTimer> timers = [];

  List<FakeTimer> get live => [
    for (final t in timers)
      if (!t.cancelled && !t.fired) t,
  ];

  List<Duration> get liveDelays => [for (final t in live) t.delay];

  @override
  CancelTimer after(Duration delay, void Function() callback) {
    final t = FakeTimer(delay, callback);
    timers.add(t);
    return () => t.cancelled = true;
  }

  /// Fires the oldest live timer with exactly [delay].
  void fire(Duration delay) => live.firstWhere((t) => t.delay == delay).fire();
}

class FakeInputs implements GuardInputsSource {
  GuardInputs value = const GuardInputs(
    ignoreRules: [],
    alwaysCaptureSenders: [],
    customTemplateSenders: [],
  );
  int reads = 0;
  Completer<void>? gate;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void set({
    List<GuardIgnoreRuleInput> rules = const [],
    List<GuardUserSenderInput> always = const [],
    List<GuardUserSenderInput> custom = const [],
  }) => value = GuardInputs(
    ignoreRules: rules,
    alwaysCaptureSenders: always,
    customTemplateSenders: custom,
  );

  @override
  Future<GuardInputs> read() async {
    reads++;
    final snapshot = value;
    final g = gate;
    if (g != null) await g.future;
    return snapshot;
  }

  @override
  Stream<void> changes() => _changes.stream;
}

class MemoryAlertStore implements AlertStore {
  PersistedAlerts value = PersistedAlerts.empty;
  int writes = 0;

  @override
  Future<PersistedAlerts> read() async => value;

  @override
  Future<void> write(PersistedAlerts next) async {
    writes++;
    value = next;
  }

  @override
  Future<void> dismissMissedNotifications() async {
    value = PersistedAlerts(
      absorbedSeq: value.absorbedSeq,
      missedNotifications: 0,
      unreadableAtMs: value.unreadableAtMs,
      catchUpFromMs: value.catchUpFromMs,
      catchUpReason: value.catchUpReason,
    );
  }
}

const GuardIgnoreRuleInput ruleNbe4567 = GuardIgnoreRuleInput(
  institutionCode: 'nbe',
  last4: '4567',
  channel: 'sms',
);

const GuardUserSenderInput senderMyBank = GuardUserSenderInput(
  sender: 'mybank',
  channel: 'sms',
);
