// L-2: the error and debugPrint muting that must exist from the first line of
// main(), before the database (and so the diag logger) can open. Release
// builds only; a debug build keeps the framework's own reporting.
//
// Errors are kept as events (code and a SafeException's constant code only,
// never the message or stack) in a small buffer and written to the diag log
// once the logger is ready. If the database never opens they are dropped with
// the process; nothing is ever printed.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'diag_code.dart';
import 'diag_error_handlers.dart';
import 'diag_event.dart';
import 'diag_logger.dart';

/// At most this many events are kept before the logger is ready.
const int earlyErrorBufferLimit = 32;

final Queue<DiagEvent> _early = Queue<DiagEvent>();

/// Installs the code-only handlers and mutes `debugPrint`. Does nothing when
/// [debugPassThrough] is true (debug builds). Synchronous, so it can be the
/// first call in `main()`.
void installEarlyErrorHandlers({bool debugPassThrough = kDebugMode}) {
  if (debugPassThrough) return;
  void keep(DiagCode base, Object error) {
    try {
      if (_early.length >= earlyErrorBufferLimit) _early.removeFirst();
      _early.addLast(diagEventForError(base, error));
    } on Object {
      // A diagnostic must not crash the app; nothing of the error is kept.
    }
  }

  FlutterError.onError = (details) =>
      keep(DiagCodes.flutterError, details.exception);
  PlatformDispatcher.instance.onError = (error, _) {
    keep(DiagCodes.uncaughtError, error);
    return true;
  };
  debugPrint = (String? message, {int? wrapWidth}) {};
}

/// Writes the buffered events to [logger] and empties the buffer.
Future<void> flushEarlyErrors(DiagLogger logger) async {
  while (_early.isNotEmpty) {
    final event = _early.removeFirst();
    try {
      await logger.record(event);
    } on Object {
      // Dropped; never surfaces.
    }
  }
}

@visibleForTesting
int get earlyErrorBufferedCount => _early.length;

@visibleForTesting
void resetEarlyErrorBuffer() => _early.clear();
