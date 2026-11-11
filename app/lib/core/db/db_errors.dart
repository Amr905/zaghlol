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

  /// T-008 (Q6): the file has no schema yet and this engine may not create
  /// one (headless engine).
  static const String createNotAllowed = 'DB_CREATE_NOT_ALLOWED';

  static const Set<String> codes = {
    keyPragmaFailed,
    keyRejected,
    notEncrypted,
    openFailed,
    leaseLapsed,
    migrationPending,
    schemaTooNew,
    migrateCopyFailed,
    createNotAllowed,
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

/// A write the database refused (T-017). Carries a constant code and the
/// SQLite extended result code only: never the statement, its parameters or
/// any row data (a raw `SqliteException` holds all three).
///
/// Constraint codes: `DB_CONSTRAINT_CHECK`, `DB_CONSTRAINT_UNIQUE`,
/// `DB_CONSTRAINT_PRIMARY_KEY`, `DB_CONSTRAINT_FOREIGN_KEY`,
/// `DB_CONSTRAINT_NOT_NULL`, `DB_CONSTRAINT_TRIGGER` (a trigger aborted with
/// an unknown message), `DB_CONSTRAINT` (other). The offset triggers
/// (financial.drift) abort with their own codes: `OFFSET_EXCEEDS_EXPENSE`,
/// `OFFSET_EXCEEDS_SOURCE`, `OFFSET_CURRENCY_MISMATCH`,
/// `OFFSET_PARTICIPANT_MISMATCH`. Any other SQLite failure is
/// `DB_WRITE_FAILED`.
final class DbWriteException extends SafeException {
  DbWriteException(super.code, {this.sqliteCode});

  static const String constraintCheck = 'DB_CONSTRAINT_CHECK';
  static const String constraintUnique = 'DB_CONSTRAINT_UNIQUE';
  static const String constraintPrimaryKey = 'DB_CONSTRAINT_PRIMARY_KEY';
  static const String constraintForeignKey = 'DB_CONSTRAINT_FOREIGN_KEY';
  static const String constraintNotNull = 'DB_CONSTRAINT_NOT_NULL';
  static const String constraintTrigger = 'DB_CONSTRAINT_TRIGGER';
  static const String constraint = 'DB_CONSTRAINT';
  static const String writeFailed = 'DB_WRITE_FAILED';

  static const String offsetExceedsExpense = 'OFFSET_EXCEEDS_EXPENSE';
  static const String offsetExceedsSource = 'OFFSET_EXCEEDS_SOURCE';
  static const String offsetCurrencyMismatch = 'OFFSET_CURRENCY_MISMATCH';
  static const String offsetParticipantMismatch = 'OFFSET_PARTICIPANT_MISMATCH';

  /// The `RAISE(ABORT, …)` messages of the schema's triggers.
  static const Set<String> triggerCodes = {
    offsetExceedsExpense,
    offsetExceedsSource,
    offsetCurrencyMismatch,
    offsetParticipantMismatch,
  };

  /// SQLite extended result code, when known.
  final int? sqliteCode;
}

/// A read the database failed (T-017 F-1). Code `DB_READ_FAILED` and the
/// SQLite extended result code only: never the statement or its parameters
/// (for search, the user's query).
final class DbReadException extends SafeException {
  DbReadException({this.sqliteCode}) : super(readFailed);

  static const String readFailed = 'DB_READ_FAILED';

  /// SQLite extended result code, when known.
  final int? sqliteCode;
}
