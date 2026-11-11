// T-148 regression (db-platform Android leg, ci/T-148 run 42982907845): the
// platform HMAC on Android (javax.crypto) rejects an empty key, so the kbkId
// HKDF with an empty salt failed with BACKUP_IO. HKDF is now always the
// pure-Dart one and an empty salt is passed as 32 zero bytes (RFC 5869 §2.2).

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/backup_primitives.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

import 'backup_test_support.dart';

/// Like the Android plugin: any platform HMAC/HKDF request fails.
final class _NoPlatformMac extends DartCryptography {
  @override
  Hmac hmac(HashAlgorithm hashAlgorithm) =>
      throw UnsupportedError('platform HMAC used');

  @override
  Hkdf hkdf({required Hmac hmac, required int outputLength}) =>
      throw UnsupportedError('platform HKDF used');
}

void main() {
  test('an empty salt equals HashLen zero bytes (RFC 5869 §2.2)', () async {
    final p = BackupPrimitives();
    final ikm = SecretBytes.copyOf(List.generate(32, (i) => i * 7));
    final a = await p.hkdf(
      ikm: ikm,
      salt: const [],
      info: keyIdInfo,
      length: 16,
    );
    final b = await p.hkdf(
      ikm: ikm,
      salt: List.filled(32, 0),
      info: keyIdInfo,
      length: 16,
    );
    expect(toHex(a.bytes), toHex(b.bytes));
  });

  test('the key schedule never uses the platform HMAC/HKDF', () async {
    final previous = Cryptography.instance;
    Cryptography.instance = _NoPlatformMac();
    addTearDown(() => Cryptography.instance = previous);
    final v = vectorCases().first;
    final kbk = SecretBytes.copyOf(hex(v['kbkHex']! as String));
    final schedule = BackupKeySchedule(BackupPrimitives());
    expect(toHex(await schedule.keyId(kbk)), v['kbkIdHex']);
    final keys = await schedule.wrap(
      kbk: kbk,
      kek: SecretBytes.copyOf(hex(v['kekHex']! as String)),
      kdf: KdfParams.v1(hex(v['saltHex']! as String)),
      wrapNonce: hex(v['wrapNonceHex']! as String),
    );
    final fileId = hex(v['fileIdHex']! as String);
    expect(toHex((await keys.chunkKey(fileId)).bytes), v['kChunkHex']);
    expect(toHex((await keys.snapshotKey(fileId)).bytes), v['kSnapHex']);
  });
}
