// T-021: global error handlers that write codes only. The message, stack and
// toString() of an error are never read, except that a SafeException's
// constant code is kept (its contract: no user data).

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
void installDiagErrorHandlers(DiagLogger logger) {
  FlutterError.onError = (details) {
    // The exception object is only inspected for being a SafeException.
    logger.record(diagEventForError(DiagCodes.flutterError, details.exception));
  };
  PlatformDispatcher.instance.onError = (error, _) {
    logger.record(diagEventForError(DiagCodes.uncaughtError, error));
    return true;
  };
  debugPrint = (String? message, {int? wrapWidth}) {};
}
