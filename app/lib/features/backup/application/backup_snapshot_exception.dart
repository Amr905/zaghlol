// T-149: typed failures of the snapshot and restore steps (design note §7).
// Code only: never a path, SQL, key, row value or file byte. Crypto failures
// keep their own BackupCryptoException.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

enum BackupSnapshotErrorCode {
  /// Another backup or restore runs in this app.
  busy('BACKUP_SNAPSHOT_BUSY'),

  /// The snapshot's schema is newer than this app (EC-26): update the app.
  newerSchema('BACKUP_SNAPSHOT_NEWER_SCHEMA'),

  /// The decrypted contents are malformed, inconsistent or fail a database
  /// check (integrity, foreign keys, schema shape, manifest). Nothing was
  /// restored.
  corruptContents('BACKUP_SNAPSHOT_CORRUPT'),

  /// The live database or its key can't be used now (retry later). Nothing
  /// was touched.
  liveUnavailable('BACKUP_SNAPSHOT_LIVE_UNAVAILABLE'),

  /// The swap transaction did not commit (busy, disk full, timeout): the old
  /// database is unchanged.
  swapFailed('BACKUP_SNAPSHOT_SWAP_FAILED'),

  /// File system or SQLite failure in the work directory.
  io('BACKUP_SNAPSHOT_IO');

  const BackupSnapshotErrorCode(this.safeCode);

  final String safeCode;
}

final class BackupSnapshotException extends SafeException {
  BackupSnapshotException(this.reason) : super(reason.safeCode);

  final BackupSnapshotErrorCode reason;
}
