import CryptoKit
import Foundation

/// AES-256-GCM over whole spool entries: `nonce(12) || ciphertext || tag(16)`
/// (the Android layout). `decrypt` throws `SpoolCipherError.notAuthentic`
/// only when the data is provably not authentic (tampered, truncated, wrong
/// key or wrong AAD); every other failure means the attempt itself failed
/// (Keychain locked or busy) and proves nothing.
enum SpoolCipherError: Error, Equatable {
  case notAuthentic
  case unavailable
}

protocol SpoolCipher {
  static var nonceBytes: Int { get }
  static var tagBytes: Int { get }
  func encrypt(_ plain: Data, aad: Data) throws -> Data
  func decrypt(_ data: Data, aad: Data) throws -> Data
  /// Creation time of the current key (epoch ms), nil when unknown.
  func keyCreatedAtMs() -> Int64?
}

extension SpoolCipher {
  static var nonceBytes: Int { 12 }
  static var tagBytes: Int { 16 }
}

/// Production cipher: the key comes only from `SpoolKeychain`.
final class KeychainSpoolCipher: SpoolCipher {
  private let keychain: SpoolKeychain
  private let lock = NSLock()
  private var cached: SpoolKeychain.Loaded?

  init(keychain: SpoolKeychain = SpoolKeychain()) { self.keychain = keychain }

  private func loaded() throws -> SpoolKeychain.Loaded {
    lock.lock()
    defer { lock.unlock() }
    if let c = cached { return c }
    do {
      let l = try keychain.loadOrCreate()
      cached = l
      return l
    } catch {
      throw SpoolCipherError.unavailable
    }
  }

  /// Forget the in-memory key (after "Delete everything").
  func reset() {
    lock.lock()
    cached = nil
    lock.unlock()
  }

  func keyCreatedAtMs() -> Int64? { try? loaded().createdAtMs }

  func encrypt(_ plain: Data, aad: Data) throws -> Data {
    let key = SymmetricKey(data: try loaded().key)
    do {
      guard let combined = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else {
        throw SpoolCipherError.unavailable
      }
      return combined
    } catch let e as SpoolCipherError {
      throw e
    } catch {
      throw SpoolCipherError.unavailable
    }
  }

  func decrypt(_ data: Data, aad: Data) throws -> Data {
    if data.count < Self.nonceBytes + Self.tagBytes { throw SpoolCipherError.notAuthentic }
    let key = SymmetricKey(data: try loaded().key)
    do {
      return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad)
    } catch CryptoKitError.authenticationFailure {
      throw SpoolCipherError.notAuthentic
    } catch CryptoKitError.incorrectParameterSize {
      throw SpoolCipherError.notAuthentic
    } catch {
      throw SpoolCipherError.unavailable
    }
  }
}
