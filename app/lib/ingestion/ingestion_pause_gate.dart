// WIRE-SVC: one gate the restore flow closes so no ingestion write (the drain
// cycle, the inbox scan) touches the database between the carry-over read and
// the file swap (FU-139). Writes in flight finish; new ones are refused with a
// transient code, so the spool keeps its entries and the next cycle retries.
// Nothing here carries message content.

import 'dart:async';

import '../features/ingestion/domain/ingest_types.dart';

/// Thrown by [IngestionPauseGate.pause] when a write did not finish in time.
final class IngestionBusyException implements Exception {
  const IngestionBusyException();
  @override
  String toString() => 'INGEST_BUSY';
}

final class IngestionPauseGate {
  bool _paused = false;
  int _active = 0;
  Completer<void>? _idle;
  final List<void Function()> _resumeListeners = [];

  bool get paused => _paused;
  bool get busy => _active > 0;

  /// Called after [resume] (the capture coordinator drains again).
  /// Returns the function that removes the listener.
  void Function() onResume(void Function() listener) {
    _resumeListeners.add(listener);
    return () => _resumeListeners.remove(listener);
  }

  /// Runs one database write. Refused (transient) while paused.
  Future<T> guard<T>(Future<T> Function() write) async {
    if (_paused) throw IngestBatchFailed(IngestBatchFailed.writeFailed);
    _active++;
    try {
      return await write();
    } finally {
      if (--_active == 0) {
        final c = _idle;
        _idle = null;
        if (c != null && !c.isCompleted) c.complete();
      }
    }
  }

  /// Stops new writes and waits for the one running. When it does not finish
  /// within [timeout] the gate reopens and this throws
  /// [IngestionBusyException]: the restore refuses rather than race a write.
  Future<void> pause({Duration timeout = const Duration(seconds: 30)}) async {
    _paused = true;
    if (_active == 0) return;
    final c = _idle ??= Completer<void>();
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      _paused = false;
      throw const IngestionBusyException();
    }
  }

  /// Reopens the gate. Safe to call when not paused.
  void resume() {
    final was = _paused;
    _paused = false;
    if (!was) return;
    for (final l in List.of(_resumeListeners)) {
      try {
        l();
      } on Object {
        // A listener must not break the restore's `finally`.
      }
    }
  }
}
