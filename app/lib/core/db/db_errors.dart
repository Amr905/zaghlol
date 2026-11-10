// T-015 / T-016: code-only database errors (error-handling §1/§3, FU-050).
// Messages never carry file paths, SQL or key material: toString() is the
// code.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// A failed open. Carries a constant code and the SQLite result code only.
///
/// Codes: `DB_KEY_PRAGMA_FAILED` (the key statement failed),
/// `DB_KEY_REJECTED` (SQLITE_NOTADB on the first page read: report it with
/// `KeyBootstrap.reportRejected`), `DB_NOT_ENCRYPTED` (the file opened but is
/// not SQLCipher-encrypted), `DB_OPEN_FAILED` (any other SQLite error during
/// the open sequence; transient, never a reason to wipe).
///
/// T-016: `DB_LEASE_LAPSED` (the bootstrap lease is no longer current:
/// `BootstrapLease.ensureValid`), `DB_MIGRATION_PENDING` (an older schema and
/// this engine may not migrate, e.g. the headless engine), `DB_SCHEMA_TOO_NEW`
/// (the file is from a newer app version, EC-26; left untouched) and
/// `DB_MIGRATE_COPY_FAILED` (the pre-migration copy could not be made; nothing
/// was migrated).
final class DbOpenException extends SafeException {
  DbOpenException(super.code, {this.sqliteCode});

  static const String keyPragmaFailed = 'DB_KEY_PRAGMA_FAILED';
  static const String keyRejected = 'DB_KEY_REJECTED';
  static const String notEncrypted = 'DB_NOT_ENCRYPTED';
  static const String openFailed = 'DB_OPEN_FAILED';
  static const String leaseLapsed = 'DB_LEASE_LAPSED';
  static const String migrationPending = 'DB_MIGRATION_PENDING';
  static const String schemaTooNew = 'DB_SCHEMA_TOO_NEW';
  static const String migrateCopyFailed = 'DB_MIGRATE_COPY_FAILED';

  static const Set<String> codes = {
    keyPragmaFailed,
    keyRejected,
    notEncrypted,
    openFailed,
    leaseLapsed,
    migrationPending,
    schemaTooNew,
    migrateCopyFailed,
  };

  final int? sqliteCode;

  /// True only for SQLITE_NOTADB on the first page read.
  bool get isKeyRejected => code == keyRejected;
}

/// A migration or schema check failed after the open sequence (T-016 §5/§6).
/// The opener restores the pre-migration copy.
///
/// Codes: `DB_NO_MIGRATION_PATH` (no step for the version pair),
/// `DB_MIGRATION_FK_VIOLATION` (`PRAGMA foreign_key_check` found rows after
/// the steps), `DB_SCHEMA_MISMATCH` (debug/test: the live schema differs from
/// a freshly created one).
final class DbMigrationException extends SafeException {
  DbMigrationException(super.code);

  static const String noMigrationPath = 'DB_NO_MIGRATION_PATH';
  static const String fkViolation = 'DB_MIGRATION_FK_VIOLATION';
  static const String schemaMismatch = 'DB_SCHEMA_MISMATCH';
}
