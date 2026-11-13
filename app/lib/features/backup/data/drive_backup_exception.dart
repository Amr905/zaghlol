// T-150 (design note §7): typed failures of the Google Drive backup host.
// Code only: never a server message, file name, id, token or byte.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

enum DriveBackupErrorCode {
  /// The OAuth client IDs are missing from this build (fail closed).
  notConfigured('DRIVE_NOT_CONFIGURED'),

  /// A background call needs a Google sign-in or a consent screen; ask the
  /// user in the foreground.
  signInRequired('DRIVE_SIGN_IN_REQUIRED'),

  /// The user closed the sign-in or consent screen.
  signInCancelled('DRIVE_SIGN_IN_CANCELLED'),

  /// Google refused the `drive.appdata` scope (or the token stayed invalid
  /// after one refresh).
  authorizationDenied('DRIVE_AUTHORIZATION_DENIED'),

  /// Internal: the token expired (401). The store refreshes once.
  authExpired('DRIVE_AUTH_EXPIRED'),

  /// No connection, a dropped connection or a timeout. Retry later.
  network('DRIVE_NETWORK'),

  /// The user's Drive storage is full.
  quotaExceeded('DRIVE_QUOTA_EXCEEDED'),

  /// Google asked us to slow down. Retry later.
  rateLimited('DRIVE_RATE_LIMITED'),

  /// Google answered 5xx or something unexpected. Retry later.
  serverError('DRIVE_SERVER_ERROR'),

  /// The file is gone.
  notFound('DRIVE_NOT_FOUND'),

  /// The uploaded bytes do not match the local file (size or MD5) or the
  /// rename did not land. The previous backups are untouched.
  uploadUnverified('DRIVE_UPLOAD_UNVERIFIED'),

  /// The file is larger than [maxBackupFileBytes].
  tooLarge('DRIVE_TOO_LARGE'),

  /// The app folder lists more files than the page cap; nothing is pruned.
  listTooLong('DRIVE_LIST_TOO_LONG'),

  /// The downloaded byte count differs from the listed size.
  corruptDownload('DRIVE_CORRUPT_DOWNLOAD'),

  /// The entry does not carry one of our backup names.
  notOurFile('DRIVE_NOT_OUR_FILE'),

  /// Another Drive backup operation runs in this app.
  busy('DRIVE_BUSY'),

  /// A local file-system failure (temp file).
  io('DRIVE_IO');

  const DriveBackupErrorCode(this.safeCode);

  final String safeCode;
}

final class DriveBackupException extends SafeException {
  DriveBackupException(this.reason) : super(reason.safeCode);

  final DriveBackupErrorCode reason;
}
