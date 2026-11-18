// T-021: global error handlers that write codes only. The message, stack and
// toString() of an error are never read, except that a SafeException's
// constant code is kept (its contract: no user data).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../db/daos/misc_daos.dart' show DiagLevel;
import 'diag_code.dart';
import 'diag_event.dart';
import 'diag_field.dart';
import 'diag_logger.dart';

DiagEvent diagEventForError(DiagCode base, Object error) => DiagEvent(
  level: DiagLevel.error,
  code: base,
  fields: [
    if (error is SafeException)
      DiagField.errorCode(DiagCode.fromSafeException(error)),
  ],
);

/// Replaces `FlutterError.onError`, `PlatformDispatcher.onError` and
/// `debugPrint` so that errors reach the diag log as codes and nothing else
/// reaches logcat. Call once per isolate, after the logger is ready.
///
/// [debugPassThrough] (FU-113 21-4): in a debug build the framework's own
/// error report and `debugPrint` stay on, so developers still see errors; the
/// code is recorded either way. Release builds pass false (the default).
///
/// Building the event can never throw out of a handler (21-3): a failure
/// there drops the record, not the app.
void installDiagErrorHandlers(
  DiagLogger logger, {
  bool debugPassThrough = false,
}) {
  void record(DiagCode base, Object error) {
    try {
      unawaited(logger.record(diagEventForError(base, error)));
    } on Object {
      // A diagnostic must not crash the app; nothing of the error is kept.
    }
  }

  FlutterError.onError = (details) {
    // The exception object is only inspected for being a SafeException.
    record(DiagCodes.flutterError, details.exception);
    if (debugPassThrough) FlutterError.dumpErrorToConsole(details);
  };
  PlatformDispatcher.instance.onError = (error, _) {
    record(DiagCodes.uncaughtError, error);
    // false in debug: the engine still reports it.
    return !debugPassThrough;
  };
  if (!debugPassThrough) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
}
