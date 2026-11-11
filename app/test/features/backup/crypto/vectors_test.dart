// T-148 §9: published library vectors (RFC 9106 §5.3 Argon2id, GCM test case
// 16, RFC 5869 case 1) and the ZGLB v1 format vectors produced by the
// independent Python generator (app/tool/backup_vectors.py).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_cipher.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/backup_primitives.dart';
import 'package:zaghlol/features/backup/crypto/backup_stream.dart';
import 'package:zaghlol/features/backup/crypto/passphrase.dart';
import 'package:zaghlol/features/backup/crypto/passphrase_kdf.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

import 'backup_test_support.dart';

void main() {
  final primitives = BackupPrimitives();

  group('published library vectors', () {
    test('RFC 9106 §5.3 Argon2id (hashlib)', () {
      final tag = argon2idRaw(
        Uint8List.fromList(List.filled(32, 0x01)),
        Uint8List.fromList(List.filled(16, 0x02)),
        32,
        3,
        4,
        secret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      expect(
        toHex(tag),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });

    test('GCM test case 16 (AES-256, 60-byte plaintext, AAD)', () async {
      final key = SecretBytes.copyOf(
        hex('feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308'),
      );
      final nonce = hex('cafebabefacedbaddecaf888');
      final pt = hex(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
      );
      final aad = hex('feedfacedeadbeeffeedfacedeadbeefabaddad2');
      const ct =
          '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
          '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662';
      const tag = '76fc6ece0f4e1768cddf8853bb2d551b';
      final sealed = await primitives.seal(
        key: key,
        nonce: nonce,
        plaintext: pt,
        aad: aad,
      );
      expect(toHex(sealed), ct + tag);
      final opened = await primitives.open(
        key: key,
        nonce: nonce,
        sealed: sealed,
        aad: aad,
      );
      expect(opened, pt);
      sealed[0] ^= 1;
      await expectLater(
        primitives.open(key: key, nonce: nonce, sealed: sealed, aad: aad),
        throwsA(isA<AeadAuthenticationFailure>()),
      );
    });

    test('RFC 5869 test case 1 (HKDF-SHA256)', () async {
      final okm = await primitives.hkdf(
        ikm: SecretBytes.copyOf(List.filled(22, 0x0b)),
        salt: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
        length: 42,
      );
      expect(
        toHex(okm.bytes),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    test('RFC 5869 test case 3 (empty salt and info)', () async {
      final okm = await primitives.hkdf(
        ikm: SecretBytes.copyOf(List.filled(22, 0x0b)),
        salt: const [],
        info: const [],
        length: 42,
      );
      expect(
        toHex(okm.bytes),
        '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d'
        '9d201395faa4b61a96c8',
      );
    });
  });

  group('ZGLB v1 format vectors (independent generator)', () {
    for (final v in vectorCases()) {
      final name = v['name']! as String;
      final schedule = BackupKeySchedule(primitives);

      test('$name: P, KEK_pass (real Argon2id), wrap, kbkId, K_chunk, '
          'K_snap, headerBlock', () async {
        final encoder = PassphraseEncoder(ArabicNfcFake());
        final p = await encoder.encode(v['passphrase']! as String);
        expect(toHex(p), v['pHex']);
        for (final alt
            in (v['equivalentPassphrases']! as List).cast<String>()) {
          expect(toHex(await encoder.encode(alt)), v['pHex'], reason: 'alt');
        }

        final kdf = KdfParams(
          salt: hex(v['saltHex']! as String),
          memoryKiB: v['memoryKiB']! as int,
          iterations: v['iterations']! as int,
          parallelism: v['parallelism']! as int,
        );
        final kek = await const Argon2idKdf().derive(p, kdf);
        expect(toHex(kek.bytes), v['kekHex']);

        final keys = await schedule.wrap(
          kbk: SecretBytes.copyOf(hex(v['kbkHex']! as String)),
          kek: kek,
          kdf: kdf,
          wrapNonce: hex(v['wrapNonceHex']! as String),
        );
        expect(toHex(keys.slot.wrappedKey), v['wrapCtHex']);
        expect(toHex(keys.slot.kbkId), v['kbkIdHex']);

        final fileId = hex(v['fileIdHex']! as String);
        expect(toHex((await keys.chunkKey(fileId)).bytes), v['kChunkHex']);
        expect(toHex((await keys.snapshotKey(fileId)).bytes), v['kSnapHex']);

        final header = BackupHeader(
          slot: keys.slot,
          fileId: fileId,
          noncePrefix: hex(v['noncePrefixHex']! as String),
          chunkSize: v['chunkSize']! as int,
          createdAtMs: v['createdAtMs']! as int,
          meta: HeaderMeta(
            seq: v['seq']! as int,
            schemaVersion: v['schemaVersion']! as int,
            contentsVersion: v['contentsVersion']! as int,
            platform: BackupPlatform.values.byName(v['platform']! as String),
            appVersion: v['appVersion']! as String,
          ),
        );
        expect(toHex(header.encodeBlock()), v['headerBlockHex']);

        // Unwrapping the vector's slot with the vector's KEK gives K_bk back.
        final unwrapped = await schedule.unwrap(slot: keys.slot, kek: kek);
        expect(
          unwrapped.sameKeyAs(SecretBytes.copyOf(hex(v['kbkHex']! as String))),
          isTrue,
        );
      });

      test(
        '$name: the Dart writer reproduces the file byte for byte',
        () async {
          final kdf = KdfParams(
            salt: hex(v['saltHex']! as String),
            memoryKiB: v['memoryKiB']! as int,
            iterations: v['iterations']! as int,
            parallelism: v['parallelism']! as int,
          );
          final keys = await schedule.wrap(
            kbk: SecretBytes.copyOf(hex(v['kbkHex']! as String)),
            kek: SecretBytes.copyOf(hex(v['kekHex']! as String)),
            kdf: kdf,
            wrapNonce: hex(v['wrapNonceHex']! as String),
          );
          final cipher = BackupCipher(
            secretStore: SlotSecretStore(),
            slotStore: MemorySlotStore(),
            normalizer: ArabicNfcFake(),
            kdf: FastKdf(),
            random: ScriptedRandom([
              hex(v['fileIdHex']! as String),
              hex(v['noncePrefixHex']! as String),
            ]),
            clock: () => DateTime.fromMillisecondsSinceEpoch(
              v['createdAtMs']! as int,
              isUtc: true,
            ),
          );
          final file = await collect(
            cipher.encrypt(
              keys,
              HeaderMeta(
                seq: v['seq']! as int,
                schemaVersion: v['schemaVersion']! as int,
                platform: BackupPlatform.values.byName(
                  v['platform']! as String,
                ),
                appVersion: v['appVersion']! as String,
              ),
              streamOf(payload(v['payloadLength']! as int), eventSize: 5000),
              chunkSize: v['chunkSize']! as int,
            ),
          );
          expect(file.length, v['fileLength']);
          expect(sha256Hex(file), v['fileSha256']);
          final (_, chunks) = splitFile(file);
          expect(chunks, hasLength(v['chunkCount']));
          expect(sha256Hex(chunks.first), v['firstChunkSha256']);
          expect(
            toHex(chunks.first.sublist(chunks.first.length - 16)),
            v['firstChunkTagHex'],
          );
          expect(sha256Hex(chunks.last), v['lastChunkSha256']);
          expect(
            toHex(chunks.last.sublist(chunks.last.length - 16)),
            v['lastChunkTagHex'],
          );
          expect(chunks.last.length, v['lastChunkLength']);
        },
      );
    }

    test(
      'the vector file (SHA-256-equal to the Python output) opens with the '
      'real KDF and every equivalent passphrase, and decrypts to the payload',
      () async {
        final v = vectorCases().first;
        final kdf = KdfParams(
          salt: hex(v['saltHex']! as String),
          memoryKiB: v['memoryKiB']! as int,
          iterations: v['iterations']! as int,
          parallelism: v['parallelism']! as int,
        );
        final keys = await BackupKeySchedule(primitives).wrap(
          kbk: SecretBytes.copyOf(hex(v['kbkHex']! as String)),
          kek: SecretBytes.copyOf(hex(v['kekHex']! as String)),
          kdf: kdf,
          wrapNonce: hex(v['wrapNonceHex']! as String),
        );
        // Rebuild the vector file (its SHA-256 must equal the Python output),
        // then decrypt it.
        final cipher = BackupCipher(
          secretStore: SlotSecretStore(),
          slotStore: MemorySlotStore(),
          normalizer: ArabicNfcFake(),
          random: ScriptedRandom([
            hex(v['fileIdHex']! as String),
            hex(v['noncePrefixHex']! as String),
          ]),
          clock: () => DateTime.fromMillisecondsSinceEpoch(
            v['createdAtMs']! as int,
            isUtc: true,
          ),
        );
        final data = payload(v['payloadLength']! as int);
        final file = await collect(
          cipher.encrypt(
            keys,
            Rig.meta(seq: v['seq']! as int, schema: v['schemaVersion']! as int),
            streamOf(data),
            chunkSize: v['chunkSize']! as int,
          ),
        );
        expect(sha256Hex(file), v['fileSha256']);
        final passphrases = [
          v['passphrase']! as String,
          ...(v['equivalentPassphrases']! as List).cast<String>(),
        ];
        for (final pass in passphrases) {
          final session = await cipher.open(
            streamOf(file),
            pass,
            maxSchemaVersion: 3,
          );
          final out = await collect(session.plaintext);
          final done = await session.done;
          expect(out, data);
          expect(done.chunks, v['chunkCount']);
          expect(done.createdAtMs, v['createdAtMs']);
          expect(toHex((await session.snapshotKey()).bytes), v['kSnapHex']);
          done.keys.zeroize();
        }
      },
    );

    test('the NFC rows are the same in the Kotlin and Swift unit tests', () {
      final rows = (loadVectors()['nfc']! as List).cast<Map<String, Object?>>();
      final kotlin = File(
        'android/app/src/test/kotlin/app/zaghlol/platform/text/'
        'TextNormalizationHostTest.kt',
      ).readAsStringSync();
      final swift = File('ios/RunnerTests/TextNormalizationTests.swift')
          .readAsStringSync();
      expect(rows, isNotEmpty);
      for (final r in rows) {
        final row = '"${r['input']}" to "${r['nfc']}"';
        final swiftRow = '("${r['input']}", "${r['nfc']}")';
        expect(kotlin, contains(row), reason: 'Kotlin is missing $row');
        expect(swift, contains(swiftRow), reason: 'Swift is missing $swiftRow');
      }
    });

    test('chunkNonce is noncePrefix ‖ u32 big-endian', () {
      final n = chunkNonce(
        Uint8List.fromList(List.filled(8, 0xaa)),
        0x01020304,
      );
      expect(toHex(n), 'aaaaaaaaaaaaaaaa01020304');
    });
  });
}
