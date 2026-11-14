// T-151 (design note §7, §8): typed failures of the iCloud backup host.
// Code only: never a native message, file name, path or byte.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

enum ICloudBackupErrorCode {
  /// No iCloud account, iCloud Drive off for the app, or the container can't
  /// be opened. The UI shows `backup_settings_errorIcloud` and offers Google
  /// Drive (see [ICloudBackupException.offersDrive]).
  unavailable('ICLOUD_UNAVAILABLE'),

  /// iCloud did not answer in time (listing, download). Retry later.
  timeout('ICLOUD_TIMEOUT'),

  /// iCloud reports the user's storage as full; the new backup is not
  /// uploaded and nothing was pruned.
  quotaExceeded('ICLOUD_QUOTA_EXCEEDED'),

  /// The file is gone.
  notFound('ICLOUD_NOT_FOUND'),

  /// The stored bytes do not match the local file (size or MD5), or the name
  /// is taken. The previous backups are untouched.
  uploadUnverified('ICLOUD_UPLOAD_UNVERIFIED'),

  /// The file is larger than `maxBackupFileBytes`.
  tooLarge('ICLOUD_TOO_LARGE'),

  /// The container lists more of our files than [maxICloudListed]; nothing
  /// is pruned.
  listTooLong('ICLOUD_LIST_TOO_LONG'),

  /// The downloaded byte count differs from the listed size.
  corruptDownload('ICLOUD_CORRUPT_DOWNLOAD'),

  /// The entry does not carry one of our backup names.
  notOurFile('ICLOUD_NOT_OUR_FILE'),

  /// Another iCloud backup operation runs in this app.
  busy('ICLOUD_BUSY'),

  /// A local or native file-system failure, or an unknown native error.
  io('ICLOUD_IO');

  const ICloudBackupErrorCode(this.safeCode);

  final String safeCode;
}

/// Our cap on listed files (native returns at most one more).
const int maxICloudListed = 1000;

final class ICloudBackupException extends SafeException {
  ICloudBackupException(this.reason) : super(reason.safeCode);

  final ICloudBackupErrorCode reason;

  /// iCloud is off on this phone: the caller offers Google Drive instead
  /// (task AC "iCloud off → clear error and Drive offer").
  bool get offersDrive => reason == ICloudBackupErrorCode.unavailable;
}
