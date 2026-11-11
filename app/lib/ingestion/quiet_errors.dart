// T-008: error handling of the ingestion engines. Uncaught errors would
// otherwise print to logcat even in release builds (with whatever text the
// error carries); here they become a fixed code only. debugPrint is muted
// too, so no framework or plugin debug text from this isolate reaches logs.

import 'package:flutter/foundation.dart';

/// Diag codes reported by [installQuietErrorHandlers].
const String uncaughtErrorCode = 'INGEST_UNCAUGHT';
const String flutterErrorCode = 'INGEST_FLUTTER_ERROR';

/// Replaces the isolate's error and debug-print hooks. [diag] receives a
/// fixed code only (T-021's logger takes these over).
void installQuietErrorHandlers(void Function(String code) diag) {
  FlutterError.onError = (_) => diag(flutterErrorCode);
  PlatformDispatcher.instance.onError = (_, _) {
    diag(uncaughtErrorCode);
    return true;
  };
  debugPrint = (String? message, {int? wrapWidth}) {};
}
