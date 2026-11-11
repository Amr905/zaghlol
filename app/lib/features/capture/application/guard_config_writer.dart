// T-047 (design note §1): builds the Guard user part on demand, hands it to
// native `writeGuardConfig` and zeroes it. Nothing keeps the bytes, a hash
// of them or anything derived (T-035 security L-2: ignore rules are
// institution + last-4, a 10^4 space, so a stored hash would be a
// fingerprint). The state this exposes is an enum and fixed codes.
//
// Triggers (owned by CaptureCoordinator): UI-engine start; the 300 ms
// trailing [onInputsChanged] from a Drift watch; [flush] called by a rule's
// writer right after its DB commit (no debounce: "rewrites before next
// capture" is `await flush()` returning); resume when dirty or not `full`.
//
// Single flight with a generation counter: [flush] completes with the
// result of a write whose build started after the call; a change during an
// in-flight write schedules exactly one more. A failed write leaves the old
// native file in force; the Dart drain-time re-check (T-046) still enforces
// BR-CAP-01 on the database side, so a failure is delayed filtering.

import 'dart:async';
import 'dart:typed_data';

import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardUserConfigBuild, buildGuardUserConfig;

import '../data/capture_host_port.dart';
import '../data/guard_inputs_reader.dart';
import '../domain/capture_health.dart';
import 'capture_scheduler.dart';

/// Retry schedule of a transient failure (design note §1).
const List<Duration> kGuardRetrySchedule = [
  Duration(seconds: 2),
  Duration(seconds: 10),
  Duration(seconds: 60),
];

/// Trailing debounce of table changes (bulk edits).
const Duration kGuardDebounce = Duration(milliseconds: 300);

/// Result of a write for the caller of [GuardConfigWriter.flush]: a rule
/// that is saved but not yet written is reported here so the rule UI can say
/// so (copy TBD, PO Q5). The rule is never rolled back (the DB is the truth).
final class GuardWriteResult {
  const GuardWriteResult(this.status);

  final GuardWriteStatus status;

  bool get ok => status.state == GuardWriteState.written;

  @override
  String toString() => 'GuardWriteResult(${status.state.name})';
}

final class GuardConfigWriter {
  GuardConfigWriter({
    required this.host,
    required this.inputs,
    required this.baseRegistryVersion,
    required this.scheduler,
    bool Function()? goldActive,
  }) : _goldActive = goldActive ?? _noGold;

  final CaptureHostPort host;
  final GuardInputsSource inputs;

  /// The bundled base's registry version (the builder checks it is sane).
  final int baseRegistryVersion;
  final CaptureScheduler scheduler;

  /// EntitlementPort until billing exists: false.
  final bool Function() _goldActive;

  static bool _noGold() => false;

  final StreamController<GuardWriteStatus> _statuses =
      StreamController<GuardWriteStatus>.broadcast();
  GuardWriteStatus _status = GuardWriteStatus.notWritten;

  int _requested = 0;
  int _covered = 0;
  Future<void>? _running;
  GuardWriteResult _last = const GuardWriteResult(GuardWriteStatus.notWritten);

  bool _dirty = false;
  CancelTimer? _debounce;
  CancelTimer? _retry;
  int _retries = 0;

  GuardWriteStatus get status => _status;
  Stream<GuardWriteStatus> get statuses => _statuses.stream;

  /// True when a change was seen that no completed write covers yet.
  bool get dirty => _dirty;

  void _set(GuardWriteStatus s) {
    _status = s;
    if (!_statuses.isClosed) _statuses.add(s);
  }

  /// A Drift watch event: rewrite after [kGuardDebounce] of quiet.
  void onInputsChanged() {
    _dirty = true;
    _debounce?.call();
    _debounce = scheduler.after(kGuardDebounce, () {
      _debounce = null;
      unawaited(flush());
    });
  }

  /// Writes now (no debounce) and completes with a write whose build started
  /// after this call. Never throws.
  Future<GuardWriteResult> flush() {
    _debounce?.call();
    _debounce = null;
    _retry?.call();
    _retry = null;
    _retries = 0;
    _dirty = true;
    return _drive();
  }

  Future<GuardWriteResult> _drive() async {
    final want = ++_requested;
    while (_covered < want) {
      final running = _running ??= _runOne().whenComplete(
        () => _running = null,
      );
      await running;
    }
    return _last;
  }

  Future<void> _runOne() async {
    final snapshot = _requested;
    GuardWriteResult result;
    try {
      result = await _writeOnce();
    } on Object {
      // Defensive: _writeOnce maps its failures; anything else is transient.
      result = const GuardWriteResult(
        GuardWriteStatus(GuardWriteState.transient, code: 'WRITE_FAILED'),
      );
      _set(result.status);
    }
    _covered = snapshot;
    _last = result;
    if (result.ok) {
      _retries = 0;
      if (_requested == snapshot) _dirty = false;
    } else if (result.status.state == GuardWriteState.transient) {
      _scheduleRetry();
    }
  }

  /// 2 s, 10 s, 60 s after a transient failure, then parked until the next
  /// trigger.
  void _scheduleRetry() {
    if (_retries >= kGuardRetrySchedule.length) {
      _set(GuardWriteStatus(GuardWriteState.parked, code: _status.code));
      _last = GuardWriteResult(_status);
      return;
    }
    _retry = scheduler.after(kGuardRetrySchedule[_retries], () {
      _retry = null;
      _retries++;
      unawaited(_drive());
    });
  }

  /// Writes, then re-reads the native state (trigger (d)): not `full` after
  /// one retry is [GuardWriteState.notEffective].
  Future<GuardWriteResult> flushAndVerify(
    Future<GuardFileState> Function() reread,
  ) async {
    var result = await flush();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!result.ok) return result;
      GuardFileState state;
      try {
        state = await reread();
      } on Object {
        return result;
      }
      if (state == GuardFileState.full) return result;
      if (attempt == 0) result = await flush();
    }
    _set(const GuardWriteStatus(GuardWriteState.notEffective));
    _last = GuardWriteResult(_status);
    return _last;
  }

  Future<GuardWriteResult> _writeOnce() async {
    final GuardInputs rows;
    try {
      rows = await inputs.read();
    } on Object {
      return _fail(
        const GuardWriteStatus(GuardWriteState.transient, code: 'DB_READ'),
      );
    }
    final GuardUserConfigBuild built = buildGuardUserConfig(
      baseRegistryVersion: baseRegistryVersion,
      ignoreRules: rows.ignoreRules,
      alwaysCaptureSenders: rows.alwaysCaptureSenders,
      customTemplateSenders: rows.customTemplateSenders,
      goldActive: _goldActive(),
    );
    final error = built.error;
    final raw = built.bytes;
    if (error != null || raw == null) {
      return _fail(
        GuardWriteStatus(
          GuardWriteState.buildFailed,
          code: error?.code.name ?? 'BUILD_FAILED',
          path: error?.path,
        ),
      );
    }
    final Uint8List bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    try {
      await host.writeGuardConfig(bytes);
      _set(GuardWriteStatus.written);
      return const GuardWriteResult(GuardWriteStatus.written);
    } on CaptureHostException catch (e) {
      return _fail(_classify(e.platformCode));
    } on Object {
      return _fail(
        const GuardWriteStatus(GuardWriteState.transient, code: 'UNKNOWN'),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      if (!identical(bytes, raw)) {
        try {
          raw.fillRange(0, raw.length, 0);
        } on Object {
          // An unmodifiable list: nothing to zero.
        }
      }
    }
  }

  GuardWriteResult _fail(GuardWriteStatus s) {
    _set(s);
    return GuardWriteResult(s);
  }

  static GuardWriteStatus _classify(String code) => switch (code) {
    'CONFIG_INVALID' => const GuardWriteStatus(
      GuardWriteState.rejected,
      code: 'CONFIG_INVALID',
    ),
    'NOT_AVAILABLE' => const GuardWriteStatus(
      GuardWriteState.unavailable,
      code: 'NOT_AVAILABLE',
    ),
    _ => GuardWriteStatus(GuardWriteState.transient, code: code),
  };

  void dispose() {
    _debounce?.call();
    _retry?.call();
    unawaited(_statuses.close());
  }
}
