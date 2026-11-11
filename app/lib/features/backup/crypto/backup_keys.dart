// T-148: the backup data key K_bk with its key slot, and the key schedule
// (design note §2, §3):
//   kbkId   = HKDF-SHA256(K_bk, salt = "", info = "ZGLB v1 key-id", 16)
//   K_chunk = HKDF-SHA256(K_bk, salt = fileId, info = "ZGLB v1 chunk", 32)
//   K_snap  = HKDF-SHA256(K_bk, salt = fileId, info = "ZGLB v1 db-snapshot", 32)
//   wrap.ct = AES-256-GCM(KEK_pass, wrap.nonce, K_bk,
//                         AAD = "ZGLB v1 wrap" ‖ CBOR(kdf) ‖ kbkId)
// Pure Dart.

import 'dart:typed_data';

import 'backup_crypto_exception.dart';
import 'backup_format.dart';
import 'backup_primitives.dart';
import 'secret_bytes.dart';

/// K_bk and its slot. The holder owns K_bk and must call [zeroize] when done.
/// Never cached in a provider (design note §8).
final class BackupKeys {
  BackupKeys._(this._kbk, this.slot, this._primitives);

  final SecretBytes _kbk;
  final KeySlot slot;
  final BackupPrimitives _primitives;

  bool get isZeroized => _kbk.isZeroized;

  /// K_chunk for [fileId]. The caller zeroes it.
  Future<SecretBytes> chunkKey(List<int> fileId) => _primitives.hkdf(
    ikm: _kbk,
    salt: fileId,
    info: chunkKeyInfo,
    length: keyLength,
  );

  /// K_snap for [fileId] (T-149: the temp snapshot DB key). The caller zeroes
  /// it.
  Future<SecretBytes> snapshotKey(List<int> fileId) => _primitives.hkdf(
    ikm: _kbk,
    salt: fileId,
    info: snapshotKeyInfo,
    length: keyLength,
  );

  /// A copy of K_bk for the secret store. The caller zeroes it.
  SecretBytes exportKey() => _kbk.clone();

  /// Constant-time comparison of K_bk.
  bool sameKeyAs(SecretBytes other) => _kbk.sameAs(other);

  void zeroize() => _kbk.zeroize();

  @override
  String toString() => 'BackupKeys(<redacted>)';
}

/// Key schedule and wrap. Stateless.
final class BackupKeySchedule {
  BackupKeySchedule(this._primitives);

  final BackupPrimitives _primitives;

  BackupPrimitives get primitives => _primitives;

  /// kbkId = HKDF(K_bk, "", "ZGLB v1 key-id", 16).
  Future<Uint8List> keyId(SecretBytes kbk) async {
    final id = await _primitives.hkdf(
      ikm: kbk,
      salt: const [],
      info: keyIdInfo,
      length: kbkIdLength,
    );
    final out = Uint8List.fromList(id.bytes);
    id.zeroize();
    return out;
  }

  /// Wraps [kbk] under [kek] and builds the slot. Takes ownership of [kbk]
  /// (it lives on in the returned keys); [kek] stays with the caller.
  Future<BackupKeys> wrap({
    required SecretBytes kbk,
    required SecretBytes kek,
    required KdfParams kdf,
    required List<int> wrapNonce,
  }) async {
    try {
      final kbkId = await keyId(kbk);
      final aadSlot = KeySlot(
        kdf: kdf,
        wrapNonce: wrapNonce,
        wrappedKey: Uint8List(wrappedKeyLength),
        kbkId: kbkId,
      );
      final sealed = await _primitives.seal(
        key: kek,
        nonce: wrapNonce,
        plaintext: kbk.bytes,
        aad: aadSlot.wrapAad(),
      );
      final slot = KeySlot(
        kdf: kdf,
        wrapNonce: wrapNonce,
        wrappedKey: sealed,
        kbkId: kbkId,
      );
      return BackupKeys._(kbk, slot, _primitives);
    } on Object {
      kbk.zeroize();
      rethrow;
    }
  }

  /// Unwraps [slot] with [kek]: a tag failure is wrongPassphrase, a
  /// fingerprint mismatch keyMismatch (design note §7 step 4).
  Future<BackupKeys> unwrap({
    required KeySlot slot,
    required SecretBytes kek,
  }) async {
    final Uint8List clear;
    try {
      clear = await _primitives.open(
        key: kek,
        nonce: slot.wrapNonce,
        sealed: slot.wrappedKey,
        aad: slot.wrapAad(),
      );
    } on AeadAuthenticationFailure {
      throw BackupCryptoException(BackupCryptoErrorCode.wrongPassphrase);
    }
    final kbk = SecretBytes.adopt(clear);
    return adopt(kbk: kbk, slot: slot);
  }

  /// Pairs a K_bk read from the secret store with its slot after checking the
  /// fingerprint in constant time. Takes ownership of [kbk]; zeroes it on
  /// failure (keyMismatch).
  Future<BackupKeys> adopt({
    required SecretBytes kbk,
    required KeySlot slot,
  }) async {
    try {
      if (kbk.length != keyLength) {
        throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
      }
      final id = await keyId(kbk);
      if (!constantTimeEquals(id, slot.kbkId)) {
        throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
      }
      return BackupKeys._(kbk, slot, _primitives);
    } on Object {
      kbk.zeroize();
      rethrow;
    }
  }
}
