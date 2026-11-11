// T-148: AES-256-GCM and HKDF-SHA256 over `package:cryptography` (design note
// §1). `AesGcm.with256bits()` resolves through `Cryptography.instance`: in the
// app, cryptography_flutter registers itself (dartPluginClass) and the OS
// AES-GCM is used (javax.crypto on Android, CryptoKit on iOS); in host tests
// the pure-Dart implementation is used. The same vectors run on both paths.
// Pure Dart: no Flutter import here.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_crypto_exception.dart';
import 'backup_format.dart';
import 'secret_bytes.dart';

/// A GCM tag check failed. Internal; mapped by the caller to the code that
/// fits the step (wrongPassphrase for the wrap, corruptData for chunks).
final class AeadAuthenticationFailure implements Exception {
  const AeadAuthenticationFailure();

  @override
  String toString() => 'AeadAuthenticationFailure';
}

final class BackupPrimitives {
  BackupPrimitives({AesGcm? aesGcm}) : _aes = aesGcm;

  final AesGcm? _aes;

  AesGcm get _gcm => _aes ?? AesGcm.with256bits();

  /// AES-256-GCM: returns `ciphertext ‖ tag`. Any library failure is `io`.
  Future<Uint8List> seal({
    required SecretBytes key,
    required List<int> nonce,
    required List<int> plaintext,
    required List<int> aad,
  }) async {
    final secretKey = SecretKeyData(
      Uint8List.fromList(key.bytes),
      overwriteWhenDestroyed: true,
    );
    try {
      final box = await _gcm.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
        aad: aad,
      );
      final ct = box.cipherText;
      final tag = box.mac.bytes;
      if (ct.length != plaintext.length || tag.length != gcmTagLength) {
        throw BackupCryptoException(BackupCryptoErrorCode.io);
      }
      final out = Uint8List(ct.length + gcmTagLength)
        ..setRange(0, ct.length, ct)
        ..setRange(ct.length, ct.length + gcmTagLength, tag);
      return out;
    } on BackupCryptoException {
      rethrow;
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    } finally {
      secretKey.destroy();
    }
  }

  /// Opens `ciphertext ‖ tag`. Throws [AeadAuthenticationFailure] on a bad tag
  /// (or input shorter than a tag), BackupCryptoException(io) on anything
  /// else.
  Future<Uint8List> open({
    required SecretBytes key,
    required List<int> nonce,
    required Uint8List sealed,
    required List<int> aad,
  }) async {
    if (sealed.length < gcmTagLength) throw const AeadAuthenticationFailure();
    final ctLength = sealed.length - gcmTagLength;
    final secretKey = SecretKeyData(
      Uint8List.fromList(key.bytes),
      overwriteWhenDestroyed: true,
    );
    try {
      final box = SecretBox(
        Uint8List.sublistView(sealed, 0, ctLength),
        nonce: nonce,
        mac: Mac(Uint8List.sublistView(sealed, ctLength)),
      );
      final clear = await _gcm.decrypt(box, secretKey: secretKey, aad: aad);
      if (clear.length != ctLength) {
        throw BackupCryptoException(BackupCryptoErrorCode.io);
      }
      return clear is Uint8List ? clear : Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const AeadAuthenticationFailure();
    } on BackupCryptoException {
      rethrow;
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    } finally {
      secretKey.destroy();
    }
  }

  /// HKDF-SHA256 (RFC 5869). An empty [salt] means "no salt" (HashLen zero
  /// bytes, RFC 5869 §2.2).
  Future<SecretBytes> hkdf({
    required SecretBytes ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) async {
    final secretKey = SecretKeyData(
      Uint8List.fromList(ikm.bytes),
      overwriteWhenDestroyed: true,
    );
    try {
      final derived = await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: length,
      ).deriveKey(secretKey: secretKey, nonce: salt, info: info);
      final data = await derived.extractBytes();
      final out = SecretBytes.copyOf(data);
      derived.destroy();
      if (out.length != length) {
        out.zeroize();
        throw BackupCryptoException(BackupCryptoErrorCode.io);
      }
      return out;
    } on BackupCryptoException {
      rethrow;
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    } finally {
      secretKey.destroy();
    }
  }
}
