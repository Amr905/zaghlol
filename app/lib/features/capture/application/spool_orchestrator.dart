// T-047 (design note §3): the UI engine's drain orchestration. One cycle at a
// time, serialised with an `again` flag (a request during a cycle gives
// exactly one more). The headless engine keeps `IngestionCycle` only; it
// never reads the spool status or clears alerts.
//
// Triggers: start, resume, `onSpoolChanged` (250 ms coalesce, any lifecycle
// state while the engine lives: the native worker waits for this event while
// a UI engine is attached, platform-channels §2), a rule change, and the
// timers below. Never a tight loop:
//  - a drain that returns nothing while `getSpoolStatus().pending > 0`
//    (the headless engine holds the claim for 60 s) is re-polled at 5 s,
//    15 s, 45 s, then left to the worker (`scheduleIngestionNow()`);
//  - `CycleOutcome.retry`: 5 s, 30 s, 2 min, then parked until the next
//    trigger;
//  - `deferred` / `noDatabase` in the UI engine: the startup gate is not
//    finished; wait for the next trigger (no timer);
//  - `ok` with `stuck > 0` is not retried (T-046 §10).
// An external trigger resets both schedules. After a cycle that stored or
// held something, and on every resume, the ingestion tables are marked
// updated (headless writes are invisible to this engine's Drift streams).

import 'dart:async';

import '../../../ingestion/ingestion_cycle.dart';
import '../data/capture_host_port.dart';
import 'capture_scheduler.dart';

const Duration kSpoolChangedCoalesce = Duration(milliseconds: 250);
const List<Duration> kPendingRepoll = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 45),
];
const List<Duration> kCycleRetry = [
  Duration(seconds: 5),
  Duration(seconds: 30),
  Duration(minutes: 2),
];

final class SpoolOrchestrator {
  SpoolOrchestrator({
    required this.drain,
    required this.host,
    required this.scheduler,
    this.afterCycle,
    this.onTablesUpdated,
  });

  /// One `IngestionCycle(mayCreateDatabase: true)` (the UI engine's runner).
  final Future<CycleResult> Function() drain;
  final CaptureHostPort host;
  final CaptureScheduler scheduler;

  /// Runs after each cycle (status read, absorb, clear, catch-up).
  final Future<void> Function(CycleResult result)? afterCycle;

  /// Marks the ingestion tables updated for Drift streams.
  final void Function()? onTablesUpdated;

  Future<void>? _loop;
  bool _again = false;
  bool _disposed = false;
  CancelTimer? _coalesce;
  CancelTimer? _timer;
  int _pollIndex = 0;
  int _retryIndex = 0;

  /// The last cycle's result (null before the first).
  CycleResult? lastResult;

  int get cyclesRun => _cycles;
  int _cycles = 0;

  /// CaptureEventsApi.onSpoolChanged.
  void onSpoolChanged() {
    if (_disposed || _coalesce != null) return;
    _coalesce = scheduler.after(kSpoolChangedCoalesce, () {
      _coalesce = null;
      unawaited(drainNow());
    });
  }

  /// `AppLifecycleState.resumed`.
  Future<void> onResumed() {
    onTablesUpdated?.call();
    return drainNow();
  }

  /// An external trigger (start, resume, rule change): resets the schedules
  /// and runs a cycle, or asks the running one for one more. Completes when
  /// the loop is idle. Never throws.
  Future<void> drainNow() {
    if (_disposed) return Future<void>.value();
    _timer?.call();
    _timer = null;
    _pollIndex = 0;
    _retryIndex = 0;
    return _request();
  }

  Future<void> _request() {
    final running = _loop;
    if (running != null) {
      _again = true;
      return running;
    }
    return _loop = _run().whenComplete(() => _loop = null);
  }

  Future<void> _run() async {
    do {
      _again = false;
      await _cycle();
    } while (_again && !_disposed);
  }

  Future<void> _cycle() async {
    CycleResult result;
    try {
      result = await drain();
    } on Object {
      result = const CycleResult(CycleOutcome.retry, code: 'INGEST_FAILED');
    }
    _cycles++;
    lastResult = result;
    if (result.drained > 0 || result.held > 0) onTablesUpdated?.call();
    try {
      await afterCycle?.call(result);
    } on Object {
      // The hook reports its own failures as state; a cycle is never lost.
    }
    if (_disposed) return;
    switch (result.outcome) {
      case CycleOutcome.ok:
        _retryIndex = 0;
        if (result.drained > 0) {
          _pollIndex = 0;
        } else {
          await _repollIfPending();
        }
      case CycleOutcome.retry:
        _scheduleTimer(
          _retryIndex < kCycleRetry.length ? kCycleRetry[_retryIndex++] : null,
        );
      case CycleOutcome.deferred:
      case CycleOutcome.noDatabase:
        break;
    }
  }

  Future<void> _repollIfPending() async {
    final int pending;
    try {
      pending = (await host.getSpoolStatus()).pending;
    } on Object {
      return;
    }
    if (pending <= 0) {
      _pollIndex = 0;
      return;
    }
    if (_pollIndex < kPendingRepoll.length) {
      _scheduleTimer(kPendingRepoll[_pollIndex++]);
      return;
    }
    // Left to the worker; never a tight loop.
    _pollIndex = 0;
    try {
      await host.scheduleIngestionNow();
    } on Object {
      // The next trigger retries.
    }
  }

  void _scheduleTimer(Duration? delay) {
    if (delay == null || _timer != null) return;
    _timer = scheduler.after(delay, () {
      _timer = null;
      if (!_disposed) unawaited(_request());
    });
  }

  void dispose() {
    _disposed = true;
    _coalesce?.call();
    _timer?.call();
    _coalesce = null;
    _timer = null;
  }
}
