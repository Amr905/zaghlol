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

/// The spool key, Keychain item `spool_key_v1` (platform-channels sections
/// 1.1 and 1.3): the **same** item the spool uses (`SpoolKeychain`: service
/// `app.zaghlol.spool`, shared access group, 32 random bytes,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable).
/// T-063 (FU-196 / 061-1): before, the Guard had its own item in the app's
/// own group, which an extension can't read; nothing wrote it in production.
///
/// Reads never create (`SpoolKeychain.existing()`); only the writer creates,
/// through the spool's own `loadOrCreate` policy.
final class KeychainSpoolKeyProvider: GuardKeyProvider {
  static let account = SpoolKeychain.account

  let keychain: SpoolKeychain

  init(keychain: SpoolKeychain = SpoolKeychain()) {
    self.keychain = keychain
  }

  func existingKey() -> GuardKeyLookup {
    switch keychain.existing() {
    case .found(let loaded): return .found(SymmetricKey(data: loaded.key))
    case .notFound: return .missing
    case .unavailable: return .unavailable
    }
  }

  func keyCreatingIfNeeded() throws -> SymmetricKey {
    do {
      return SymmetricKey(data: try keychain.loadOrCreate().key)
    } catch {
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
