// Pigeon contract: secret store (T-015). Native Keystore/Keychain storage for
// device-only secrets; today only the database key `K_db` (T-148 adds the
// backup key). Contract and error codes: docs/03-technical/platform-channels.md
// §5 and §6; design: docs/04-tasks/tasks/T-015.md "Design note" §2.
// Regenerate with app/tool/generate_pigeon.sh; CI fails when the generated
// files are stale.
//
// Rules for the native side (both platforms):
// - Only positive evidence of absence is `notFound` and only positive evidence
//   of corruption or a lost wrapping key is `unusable`. Every unknown error is
//   `unavailable` and must never lead to a wipe.
// - Errors cross the boundary as PlatformException(code, message: null):
//   `KEY_STORE_FAILED` or `LEASE_TIMEOUT`. Native exception messages and causes
//   are dropped. Nothing in the keys code logs.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/secret_store_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/keys/SecretStoreApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.keys',
      errorClassName: 'SecretStoreApiError',
    ),
    swiftOut: 'ios/Runner/Platform/SecretStoreApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'SecretStoreApiError'),
  ),
)
/// The secrets the store knows. Each slot maps to one fixed native location.
enum SecretSlotMsg { dbKey }

/// Result class of a read.
enum SecretStatusMsg {
  /// The secret exists and was read; `value` holds it.
  found,

  /// Positive evidence that no secret was ever stored (or it was deleted).
  notFound,

  /// Positive evidence that a stored secret can never be read again (wrapping
  /// key missing or invalidated, authentication tag failure, malformed blob).
  unusable,

  /// Anything else, after the native retries. Never a reason to wipe.
  unavailable,
}

class SecretReadMsg {
  SecretReadMsg({required this.status, this.value, required this.attempts});

  SecretStatusMsg status;

  /// Set only when [status] is `found`.
  Uint8List? value;

  /// How many native attempts the read took (1 when the first one answered).
  int attempts;
}

@HostApi()
abstract class SecretStoreHostApi {
  /// Takes the process-wide bootstrap lease, waiting at most [timeoutMs].
  /// Returns the lease id. A lease expires 30 s after it was taken. Fails with
  /// `LEASE_TIMEOUT` when the lease could not be taken in time.
  @async
  int acquireBootstrapLease(int timeoutMs);

  /// Releases [lease]. A stale or unknown lease is ignored.
  @async
  void releaseBootstrapLease(int lease);

  /// Reads [slot]. Never throws for storage errors: they are classified.
  @async
  SecretReadMsg read(SecretSlotMsg slot);

  /// Stores [candidate] in [slot] unless a usable secret is already there, and
  /// returns the stored value (the existing one wins). The value is read back
  /// and compared before this returns. Fails with `LEASE_TIMEOUT` when [lease]
  /// is not the current lease, or `KEY_STORE_FAILED`.
  @async
  Uint8List createIfAbsent(int lease, SecretSlotMsg slot, Uint8List candidate);

  /// Deletes [slot] only (never anything else). Idempotent. Fails with
  /// `LEASE_TIMEOUT` when [lease] is not the current lease, or
  /// `KEY_STORE_FAILED`.
  @async
  void delete(int lease, SecretSlotMsg slot);
}
