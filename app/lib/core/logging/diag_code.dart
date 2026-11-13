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

  /// Re-reads a stored code (export): the [DiagCodes] entry with that value,
  /// or `null`. It never builds a new instance, so text read back from a row
  /// cannot become a code.
  static DiagCode? fromRegistry(Object? raw) {
    if (raw is! String) return null;
    for (final c in DiagCodes.all) {
      if (c.value == raw) return c;
    }
    return null;
  }

  /// Whether [raw] has the shape of an error code (a [SafeException] code
  /// stored as an `error_code` field value). A shape check only.
  static bool hasCodeShape(Object? raw) =>
      raw is String && _shape.hasMatch(raw);

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
  /// Every registered code. Keep in step with the constants below; the export
  /// drops a stored row code that is not in this list.
  static const List<DiagCode> all = [
    flutterError,
    uncaughtError,
    unknownError,
    appStarted,
    ingestCycle,
    ingestUncaught,
    ingestFlutterError,
    syncOk,
    syncFailed,
    catalogUpdated,
    dbMigrated,
    backupExclusionFailed,
    backendCallFailed,
    backendBadSignature,
    installReregistered,
    entitlementSubMismatch,
    accountIidMismatch,
  ];

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

  /// T-141: a backend call failed (fields: `http_status` when there was one).
  static const DiagCode backendCallFailed = DiagCode._('BACKEND_CALL_FAILED');

  /// T-141: a signed operation's answer was dropped (bad or missing
  /// `Zaghlol-Signature`).
  static const DiagCode backendBadSignature = DiagCode._(
    'BACKEND_BAD_SIGNATURE',
  );

  /// T-141 (R5-1): the install token was refused and a new install ID was
  /// registered; local data kept.
  static const DiagCode installReregistered = DiagCode._(
    'INSTALL_REREGISTERED',
  );

  /// T-144 (R5-1): a validly signed entitlement token named another install;
  /// ignored. A counter only: no token, no ID.
  static const DiagCode entitlementSubMismatch = DiagCode._(
    'ENTITLEMENT_SUB_MISMATCH',
  );

  /// T-144 (R5-1): a signed account token named another install; ignored.
  static const DiagCode accountIidMismatch = DiagCode._('ACCOUNT_IID_MISMATCH');
}
