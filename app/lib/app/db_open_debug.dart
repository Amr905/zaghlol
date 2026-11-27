// FREEZE-FIX: debug builds name a failed database open in the console, so a
// device run shows why start-up stopped (`flutter run` / `adb logcat -s
// flutter`). Codes and versions only, never a path, statement or row.
// `kDebugMode` is a compile-time constant, so release builds drop it.

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../core/db/app_database_opener.dart';

void dbOpenProbe(DbOpenFailure failure) {
  if (kDebugMode) debugPrint('ZAGHLOL_DB_OPEN_FAILED ${failure.summary}');
}
