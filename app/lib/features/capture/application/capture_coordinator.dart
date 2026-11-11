// T-047: composes the capture module of the UI engine: capabilities, the
// Guard config writer, the spool orchestrator, absorb-then-clear of native
// alerts, the catch-up port, and the share-intake hooks (FU-067) and
// soft-delete purge (FU-076). It feeds `deriveCaptureHealth`; it holds no
// message, sender or user-part byte, only enums, counts and codes.
//
// Order at start (design note §3): capabilities, status read, config write,
// drain, status read/absorb/clear. Only the UI engine runs this class.

import 'dart:async';

import '../../../core/platform/capture_api.g.dart';
import '../../../ingestion/ingestion_cycle.dart';
import '../data/alert_store.dart';
import '../data/capture_host_port.dart';
import '../data/catch_up_scheduler.dart';
import '../domain/alert_absorb.dart';
import '../domain/capture_health.dart';
import 'capture_scheduler.dart';
import 'guard_config_writer.dart';
import 'spool_orchestrator.dart';

/// Startup and resume hooks of other modules, owned here (FU-067, FU-076).
final class CaptureHooks {
  const CaptureHooks({
    this.attachShareIntake,
    this.pollShareIntake,
    this.purgeExpired,
  });

  /// `ShareIntakeService.attach()`.
  final void Function()? attachShareIntake;

  /// `ShareIntakeService.pollPending()`: at start and on every resume.
  final Future<void> Function()? pollShareIntake;

  /// `TransactionRepository.purgeExpired()`: once per start, after the first
  /// drain.
  final Future<void> Function()? purgeExpired;
}

final class CaptureCoordinator implements CaptureEventsApi {
  CaptureCoordinator({
    required this.host,
    required this.writer,
    required this.alerts,
    required Future<CycleResult> Function() drain,
    required CaptureScheduler scheduler,
    CatchUpScheduler? catchUp,
    this.hooks = const CaptureHooks(),
    void Function()? onTablesUpdated,
    int Function()? nowMs,
    CaptureToggles initialToggles = const CaptureToggles(
      sms: true,
      notifications: true,
    ),
  }) : _toggles = initialToggles,
       catchUp = catchUp ?? RecordingCatchUpScheduler(),
       _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch) {
    orchestrator = SpoolOrchestrator(
      drain: drain,
      host: host,
      scheduler: scheduler,
      afterCycle: _afterCycle,
      onTablesUpdated: onTablesUpdated,
    );
    _writeSub = writer.statuses.listen((_) => _emit());
  }

  final CaptureHostPort host;
  final GuardConfigWriter writer;
  final AlertStore alerts;
  final CatchUpScheduler catchUp;
  final CaptureHooks hooks;
  late final SpoolOrchestrator orchestrator;
  final int Function() _nowMs;
  StreamSubscription<GuardWriteStatus>? _writeSub;

  final StreamController<CaptureHealth> _health =
      StreamController<CaptureHealth>.broadcast();
  CaptureCaps _caps = CaptureCaps.none;
  CaptureToggles _toggles;
  PersistedAlerts _persisted = PersistedAlerts.empty;
  LastCycle _lastCycle = LastCycle.none;
  GuardFileState _guardState = GuardFileState.unknown;
  CaptureHealth _current = CaptureHealth.initial;
  bool _started = false;
  bool _purged = false;

  CaptureHealth get health => _current;
  Stream<CaptureHealth> get healthChanges => _health.stream;
  PersistedAlerts get persistedAlerts => _persisted;

  // ---- lifecycle ---------------------------------------------------------

  /// Start of the UI engine, after the database gate opened.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _refreshCapabilities();
    hooks.attachShareIntake?.call();
    await _safe(hooks.pollShareIntake);
    _persisted = await _safeRead();
    _emit();
    final needsRewrite = await _readStatus(absorb: true);
    // Unconditional write (also with zero rows, so native reports `full`).
    if (needsRewrite) {
      await writer.flushAndVerify(_rereadGuardState);
    } else {
      await writer.flush();
    }
    await orchestrator.drainNow(); // _afterCycle: status, absorb, clear
    if (!_purged) {
      _purged = true;
      await _safe(hooks.purgeExpired);
    }
    _emit();
  }

  /// `AppLifecycleState.resumed`.
  Future<void> onResumed() async {
    if (!_started) return;
    await _refreshCapabilities();
    await _safe(hooks.pollShareIntake);
    final needsRewrite = await _readStatus(absorb: true);
    if (needsRewrite || writer.dirty || _guardState != GuardFileState.full) {
      await writer.flushAndVerify(_rereadGuardState);
    }
    await orchestrator.onResumed();
  }

  /// Called by the writer of a rule (T-078, T-049, the picker) right after
  /// its DB commit. Completes when the config is written (or failed) and the
  /// waiting entries were re-checked; the rule is not rolled back.
  Future<GuardWriteResult> onRuleChanged() async {
    final result = await writer.flush();
    unawaited(orchestrator.drainNow());
    return result;
  }

  /// A Drift watch event on the three tables.
  void onGuardInputsChanged() => writer.onInputsChanged();

  void setToggles(CaptureToggles toggles) {
    _toggles = toggles;
    _emit();
  }

  /// The user dismissed the missed-notification notice (count only).
  Future<void> dismissMissedNotifications() async {
    await alerts.dismissMissedNotifications();
    _persisted = await _safeRead();
    _emit();
  }

  // ---- CaptureEventsApi --------------------------------------------------

  @override
  void onSpoolChanged(int pendingCount) => orchestrator.onSpoolChanged();

  /// A permission change updates the health only; it does not write.
  @override
  void onPermissionChanged(CaptureCapabilities c) {
    _caps = _capsOf(c);
    _emit();
  }

  // ---- internals ---------------------------------------------------------

  Future<void> _afterCycle(CycleResult result) async {
    _lastCycle = LastCycle(stuck: result.stuck, held: result.held);
    final needsRewrite = await _readStatus(absorb: true);
    // A rewrite that was already tried and is not effective waits for a
    // different trigger (resume, a rule change) instead of repeating per
    // cycle.
    if (needsRewrite && writer.status.state != GuardWriteState.notEffective) {
      await writer.flushAndVerify(_rereadGuardState);
    }
    if (_smsActive) await _safe(catchUp.requestIfPending);
    _emit();
  }

  bool get _smsActive =>
      _current.channels[CaptureChannel.smsLive] == ChannelState.active;

  Future<void> _refreshCapabilities() async {
    try {
      _caps = _capsOf(await host.getCapabilities());
    } on Object {
      // Keep the last known capabilities.
    }
    _emit();
  }

  static CaptureCaps _capsOf(CaptureCapabilities c) => CaptureCaps(
    smsFlavor: c.smsFlavor,
    smsGranted: c.smsGranted,
    notificationAccess: c.notificationAccess,
  );

  static GuardFileState _stateOf(GuardConfigState s) => switch (s) {
    GuardConfigState.unknown => GuardFileState.unknown,
    GuardConfigState.full => GuardFileState.full,
    GuardConfigState.baseOnly => GuardFileState.baseOnly,
    GuardConfigState.userUnreadable => GuardFileState.userUnreadable,
    GuardConfigState.baseInvalid => GuardFileState.baseInvalid,
  };

  Future<GuardFileState> _rereadGuardState() async {
    final s = await host.getSpoolStatus();
    _guardState = _stateOf(s.guardState);
    _emit();
    return _guardState;
  }

  /// Reads the native status, absorbs the alerts (store, then clear) and
  /// reports whether the Guard config must be rewritten at once
  /// (`userUnreadable` or `keyInvalidatedAtMs`, trigger (d)).
  Future<bool> _readStatus({required bool absorb}) async {
    final SpoolStatus s;
    try {
      s = await host.getSpoolStatus();
    } on Object {
      return false;
    }
    _guardState = _stateOf(s.guardState);
    final rewrite =
        _guardState == GuardFileState.userUnreadable ||
        s.keyInvalidatedAtMs != null;
    if (absorb) await _absorb(s);
    _emit();
    return rewrite;
  }

  Future<void> _absorb(SpoolStatus s) async {
    try {
      _persisted = await alerts.read();
      final plan = planAbsorb(
        snapshot: AlertSnapshot(
          seq: s.seq,
          missedNotifications: s.missedNotifications,
          decryptDeleted: s.decryptDeleted,
          firstMissedSmsAtMs: s.firstMissedSmsAtMs,
          keyInvalidatedAtMs: s.keyInvalidatedAtMs,
        ),
        persisted: _persisted,
        nowMs: _nowMs(),
      );
      switch (plan) {
        case AbsorbNothing():
          return;
        case AbsorbRetryClear(:final seq):
          await host.clearSpoolAlerts(seq);
        case AbsorbStore(:final next, :final seq):
          await alerts.write(next);
          _persisted = next;
          await host.clearSpoolAlerts(seq);
      }
    } on Object {
      // A failed store: nothing is cleared, the next read tries again. A
      // failed clear: the stored seq makes the next read retry the clear
      // only.
    }
  }

  Future<PersistedAlerts> _safeRead() async {
    try {
      return await alerts.read();
    } on Object {
      return _persisted;
    }
  }

  static Future<void> _safe(Future<void> Function()? f) async {
    if (f == null) return;
    try {
      await f();
    } on Object {
      // A hook of another module failed; capture goes on.
    }
  }

  void _emit() {
    final next = deriveCaptureHealth(
      caps: _caps,
      toggles: _toggles,
      absorbed: AbsorbedAlerts(
        missedNotifications: _persisted.missedNotifications,
        unreadableAtMs: _persisted.unreadableAtMs,
      ),
      guardWrite: writer.status,
      lastCycle: _lastCycle,
      guardState: _guardState,
    );
    if (next == _current) return;
    _current = next;
    if (!_health.isClosed) _health.add(next);
  }

  Future<void> dispose() async {
    orchestrator.dispose();
    writer.dispose();
    await _writeSub?.cancel();
    await _health.close();
  }
}
