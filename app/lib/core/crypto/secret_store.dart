// T-015: the secure-storage abstraction for device-only secrets (security
// model §3). Pure Dart: the Pigeon implementation is PigeonSecretStore in
// core/platform/, tests use a fake. Nothing here logs, and no type here prints
// secret bytes.

import 'dart:typed_data';

/// The secrets the store knows (platform-channels §5).
enum SecretSlot {
  /// K_db, the database key (T-015).
  dbKey,

  /// K_bk, the backup data key (T-148; security-model §3).
  backupKey,
}

/// How a read ended (platform-channels §5, "Secret store").
enum SecretStatus {
  /// The secret exists and was read.
  found,

  /// Positive evidence that no secret is stored.
  notFound,

  /// Positive evidence that the stored secret can never be read again
  /// (wrapping key missing or invalidated, tag failure, malformed blob).
  unusable,

  /// Anything else, after the native retries. Never a reason to wipe.
  unavailable,
}

/// The result of [SecretStore.read]. [value] is set only for
/// [SecretStatus.found]; the receiver owns it and must zero it after use.
final class SecretRead {
  SecretRead(this.status, {this.value, this.attempts = 1})
    : assert(
        (status == SecretStatus.found) == (value != null),
        'value is set exactly when the status is found',
      );

  final SecretStatus status;
  final Uint8List? value;
  final int attempts;

  @override
  String toString() => 'SecretRead(${status.name}, attempts: $attempts)';
}

/// Why a store call failed. Codes only; no native message crosses over.
enum SecretStoreErrorCode {
  /// The bootstrap lease could not be taken in time, or the lease passed to a
  /// write is no longer the current one (`LEASE_TIMEOUT`).
  leaseTimeout,

  /// The native store could not write, verify or delete (`KEY_STORE_FAILED`).
  storeFailed,

  /// Any other failure, e.g. the channel is not registered in this engine.
  unavailable,
}

/// A failed [SecretStore] call. Carries a code only.
final class SecretStoreException implements Exception {
  const SecretStoreException(this.code);

  final SecretStoreErrorCode code;

  @override
  String toString() => 'SecretStoreException(${code.name})';
}

/// A held bootstrap lease (process-wide, shared by every engine). It expires
/// natively 30 s after it was taken.
final class SecretStoreLease {
  SecretStoreLease(this.id);

  final int id;

  @override
  String toString() => 'SecretStoreLease($id)';
}

/// Native Keystore/Keychain storage for device-only secrets.
///
/// Implementations never log and never cache secret bytes.
abstract interface class SecretStore {
  /// Takes the process-wide bootstrap lease. Throws [SecretStoreException]
  /// ([SecretStoreErrorCode.leaseTimeout] when it was not free in time).
  Future<SecretStoreLease> acquireBootstrapLease(Duration timeout);

  /// Releases [lease]. Never throws.
  Future<void> releaseBootstrapLease(SecretStoreLease lease);

  /// T-016 (S-2, FU-065): if [lease] is still the current, unexpired lease,
  /// extends its expiry to now + 30 s and returns true; otherwise returns
  /// false (it never takes a lease). Never throws: a failed call is false.
  Future<bool> renewBootstrapLease(SecretStoreLease lease);

  /// Reads [slot]. Never throws: every failure is a [SecretStatus].
  Future<SecretRead> read(SecretSlot slot);

  /// Stores [candidate] unless a usable secret is already in [slot], and
  /// returns the stored value (the existing one wins). Throws
  /// [SecretStoreException].
  Future<Uint8List> createIfAbsent(
    SecretStoreLease lease,
    SecretSlot slot,
    Uint8List candidate,
  );

  /// Deletes [slot] only. Idempotent. Throws [SecretStoreException].
  Future<void> delete(SecretStoreLease lease, SecretSlot slot);
}
