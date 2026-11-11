// T-148: typed failures of the backup crypto module (design note §8). Codes
// only: no message, no key bytes, no passphrase, no header bytes, no file id
// and no plaintext ever reach an exception, its toString or a log. The UI maps
// codes to copy; this layer holds no user-facing strings.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// Why a backup crypto call failed (design note §7, §8).
enum BackupCryptoErrorCode {
  /// The file does not start with the "ZGLB" magic.
  notABackup('BACKUP_NOT_A_BACKUP'),

  /// A newer format or contents version: the app must be updated (EC-26).
  newerFormat('BACKUP_NEWER_FORMAT'),

  /// The snapshot's DB schema is newer than this app supports (EC-26).
  newerSchema('BACKUP_NEWER_SCHEMA'),

  /// The prefix or the CBOR header is malformed or non-canonical.
  corruptHeader('BACKUP_CORRUPT_HEADER'),

  /// The KDF algorithm or its parameters are outside the accepted bounds;
  /// refused before the KDF runs.
  unsupportedKdf('BACKUP_UNSUPPORTED_KDF'),

  /// The passphrase does not unwrap the key (or the wrap was corrupted, which
  /// reads the same).
  wrongPassphrase('BACKUP_WRONG_PASSPHRASE'),

  /// The unwrapped key does not match its fingerprint, the device's stored
  /// backup key is missing, unusable or does not match the local key slot, or
  /// a file was written with another key. The next manual backup asks for the
  /// passphrase (design note §3 "Recovery").
  keyMismatch('BACKUP_KEY_MISMATCH'),

  /// A chunk failed authentication, is out of place, or the file was cut.
  corruptData('BACKUP_CORRUPT_DATA'),

  /// The KDF could not allocate its memory; retryable (close other apps).
  kdfOutOfMemory('BACKUP_KDF_OUT_OF_MEMORY'),

  /// The secret store or the key slot store could not answer; retry later,
  /// never re-key.
  keyUnavailable('BACKUP_KEY_UNAVAILABLE'),

  /// The new passphrase has fewer than 8 characters after normalization
  /// (security-model §5). Added by the implementation (not in the note's
  /// list): the crypto layer must refuse it even if the UI checks first.
  passphraseTooShort('BACKUP_PASSPHRASE_TOO_SHORT'),

  /// Reading the input, the platform crypto or the normalizer failed.
  io('BACKUP_IO');

  const BackupCryptoErrorCode(this.safeCode);

  /// The UPPER_SNAKE_CASE code carried by [SafeException].
  final String safeCode;
}

/// A failed backup crypto operation. Carries a code only.
final class BackupCryptoException extends SafeException {
  BackupCryptoException(this.reason) : super(reason.safeCode);

  final BackupCryptoErrorCode reason;
}
