import CryptoKit
import Foundation
import Security

/// Why a decrypt failed. `authentication` is proof the file is unusable
/// (tampered, truncated, wrong key, wrong AAD, or its key no longer exists);
/// anything else means the attempt failed and may be retried.
enum GuardCipherError: Error {
  case authentication
  case unavailable
}

/// AES-256-GCM for the Guard user part (T-038 design note section 5). Format
/// `nonce(12) || ciphertext || tag(16)` (CryptoKit `SealedBox.combined`),
/// AAD `GuardUserConfigStore.aad`.
protocol GuardUserCipher {
  func encrypt(_ plain: Data, aad: Data) throws -> Data
  func decrypt(_ data: Data, aad: Data) throws -> Data
}

enum GuardUserCipherFormat {
  static let nonceBytes = 12
  static let tagBytes = 16
}

/// Where the cipher gets its key.
enum GuardKeyLookup {
  case found(SymmetricKey)
  /// Positive evidence that no key exists.
  case missing
  /// Could not read now (before first unlock, Keychain busy): retry later.
  case unavailable
}

protocol GuardKeyProvider {
  /// The key if it exists; never creates one (a read before the first unlock
  /// must not mint a key that would orphan an existing file).
  func existingKey() -> GuardKeyLookup
  /// The key, created if none exists (writer only).
  func keyCreatingIfNeeded() throws -> SymmetricKey
}

/// The spool key, Keychain item `spool_key_v1` (32 random bytes,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; platform-channels
/// section 1.3). Built on the K_db slot store with another account, so the
/// attributes, retries and no-overwrite rules are the same ones T-015 tests.
///
/// T-062 owns the spool and the shared access group: it passes the group
/// through `slot` once the App Group / keychain-access-groups entitlement
/// exists. Until then the item lives in the app's own group.
final class KeychainSpoolKeyProvider: GuardKeyProvider {
  static let account = "spool_key_v1"

  private let slot: SecretSlotStore

  init(slot: SecretSlotStore = DbKeyKeychain(account: KeychainSpoolKeyProvider.account)) {
    self.slot = slot
  }

  func existingKey() -> GuardKeyLookup {
    let r = slot.read()
    switch r.status {
    case .found:
      guard let value = r.value else { return .unavailable }
      return .found(SymmetricKey(data: value))
    case .notFound:
      return .missing
    case .unusable, .unavailable:
      // Never a reason to wipe or to recreate here: T-062 owns that policy.
      return .unavailable
    }
  }

  func keyCreatingIfNeeded() throws -> SymmetricKey {
    switch existingKey() {
    case .found(let key):
      return key
    case .missing:
      var bytes = [UInt8](repeating: 0, count: DbKeyKeychain.keyLength)
      let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
      guard status == errSecSuccess else { throw GuardCipherError.unavailable }
      let stored = try slot.createIfAbsent(Data(bytes))
      return SymmetricKey(data: stored)
    case .unavailable:
      throw GuardCipherError.unavailable
    }
  }
}

/// `GuardUserCipher` over CryptoKit AES-GCM with a `GuardKeyProvider` key.
struct AesGcmGuardUserCipher: GuardUserCipher {
  let keys: GuardKeyProvider

  func encrypt(_ plain: Data, aad: Data) throws -> Data {
    let key = try keys.keyCreatingIfNeeded()
    let box = try AES.GCM.seal(plain, using: key, authenticating: aad)
    guard let combined = box.combined else { throw GuardCipherError.unavailable }
    return combined
  }

  func decrypt(_ data: Data, aad: Data) throws -> Data {
    if data.count < GuardUserCipherFormat.nonceBytes + GuardUserCipherFormat.tagBytes {
      throw GuardCipherError.authentication
    }
    let key: SymmetricKey
    switch keys.existingKey() {
    case .found(let k): key = k
    case .missing: throw GuardCipherError.authentication
    case .unavailable: throw GuardCipherError.unavailable
    }
    do {
      let box = try AES.GCM.SealedBox(combined: data)
      return try AES.GCM.open(box, using: key, authenticating: aad)
    } catch {
      throw GuardCipherError.authentication
    }
  }
}
