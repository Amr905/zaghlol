// T-021: the allow-list of diagnostic event codes (error-handling-and-
// observability §3.1). A [DiagCode] cannot be built from an arbitrary String
// outside this library: the only instances are the `static const` entries of
// [DiagCodes] (plus [DiagCode.fromSafeException], which re-checks the shape).

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// A fixed event or error code, UPPER_SNAKE_CASE, at most 64 characters.
final class DiagCode {
  const DiagCode._(this.value);

  /// The code of a [SafeException] (its constant, data-free code). Anything
  /// that is not UPPER_SNAKE_CASE falls back to [DiagCodes.unknownError].
  factory DiagCode.fromSafeException(SafeException e) =>
      _shape.hasMatch(e.code) ? DiagCode._(e.code) : DiagCodes.unknownError;

  /// Re-reads a stored code (export). `null` when the shape is wrong.
  static DiagCode? tryFromStored(Object? raw) =>
      raw is String && _shape.hasMatch(raw) ? DiagCode._(raw) : null;

  static final RegExp _shape = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  final String value;

  @override
  bool operator ==(Object other) => other is DiagCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The registry of codes the app may log. Adding one is a reviewed code
/// change; there is deliberately no way to log a code built at run time.
abstract final class DiagCodes {
  static const DiagCode flutterError = DiagCode._('FLUTTER_ERROR');
  static const DiagCode uncaughtError = DiagCode._('UNCAUGHT_ERROR');
  static const DiagCode unknownError = DiagCode._('UNKNOWN_ERROR');
  static const DiagCode appStarted = DiagCode._('APP_STARTED');
  static const DiagCode ingestCycle = DiagCode._('INGEST_CYCLE');
  static const DiagCode ingestUncaught = DiagCode._('INGEST_UNCAUGHT');
  static const DiagCode ingestFlutterError = DiagCode._('INGEST_FLUTTER_ERROR');
  static const DiagCode syncOk = DiagCode._('SYNC_OK');
  static const DiagCode syncFailed = DiagCode._('SYNC_FAILED');
  static const DiagCode catalogUpdated = DiagCode._('CATALOG_UPDATED');
  static const DiagCode dbMigrated = DiagCode._('DB_MIGRATED');

  /// T-165 (Swift `BackupExclusion`): excluding a data directory from OS
  /// backups failed. Code only, never a path.
  static const DiagCode backupExclusionFailed = DiagCode._(
    'BACKUP_EXCLUSION_FAILED',
  );
}
