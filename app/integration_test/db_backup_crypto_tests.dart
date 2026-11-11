// T-148 §9: the ZGLB v1 vectors on the real platform: the OS AES-GCM
// (cryptography_flutter: javax.crypto on Android, CryptoKit on iOS) for the
// 64 KiB chunks, the native NFC (TextNormalizationHostApi) for the passphrase,
// and Argon2id compiled for the device. Registered by db_platform_test.dart,
// so db-platform.yml runs it on the Android emulators and the iOS simulator.
// The constants are case 0 of app/test/fixtures/backup/zglb-v1-vectors.json
// (a host test, backup_device_vectors_sync_test.dart, keeps them equal).
//
// Hygiene: synthetic values only; the only output line is ZAGHLOL_KDF_MS.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/pigeon_text_normalizer.dart';
import 'package:zaghlol/features/backup/crypto/backup_cipher.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/backup_primitives.dart';
import 'package:zaghlol/features/backup/crypto/passphrase.dart';
import 'package:zaghlol/features/backup/crypto/passphrase_kdf.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

import '../test/features/backup/crypto/backup_test_support.dart';

/// Case 0 ("arabic-2.5-chunks-64k").
abstract final class DeviceVector {
  static const String passphrase =
      'كلمة سر ٣٤۵ '
      'أمان';
  static const String saltHex = 'e781f5d4484d8599d3d13c2ea5cd547d';
  static const String kbkHex =
      '902eefeb1d624e098ad91e74f960cfed7268ddb0c6be1ccb12ccd6111e3c2497';
  static const String wrapNonceHex = '9f7ffbf86fc35fe2ad47cbb5';
  static const String fileIdHex = 'ab4cccac2856b379f3e501a1199e1d6b';
  static const String noncePrefixHex = '86976a56f3554b98';
  static const int createdAtMs = 1762848000001;
  static const String pHex =
      'd983d984d985d8a920d8b3d8b12033343520d8a3d985d8a7d986';
  static const String kekHex =
      '98643ce8a752551525a2e04ba52a6168f8b2bf285e4335254980b7393537e9a1';
  static const String wrapCtHex =
      '001d67ffe4ec941cd6be41d014f02ad21cbacfa7d9fa4c6808202c2591352417'
      'e2d3fec372a836f04eb7cef93435bdaf';
  static const String kbkIdHex = 'a14be5a1865c97b4f42ea992e0c21741';
  static const String kChunkHex =
      '1be9d5f1d20fe933eb41ec0ffb0934a780ee0cb58714ecb13dd2152829c1c493';
  static const String kSnapHex =
      'ae6859537fe5fb25e105accb7bcba79dd859f57d65b49f876d05032cf8fbcb3b';
  static const String fileSha256 =
      '9aa55b9761cd147ea78dd2bab09ae1b946f5ed1de8297ca6c31bffc85b2eb9f7';
  static const int payloadLength = 163840;
  static const int chunkSize = 65536;
  static const int seq = 7;
  static const int schemaVersion = 3;
  static const String appVersion = '0.1.0+1';

  /// The shared NFC rows (code points, hex).
  static const List<(String, String)> nfcRows = [
    ('0627 0653', '0622'),
    ('0627 0654', '0623'),
    ('0648 0654', '0624'),
    ('0627 0655', '0625'),
    ('064A 0654', '0626'),
    ('06D5 0654', '06C0'),
    ('06C1 0654', '06C2'),
    ('06D2 0654', '06D3'),
    ('0623', '0623'),
    ('0647 0645 0632 0629', '0647 0645 0632 0629'),
    ('0628 0651 0650', '0628 0650 0651'),
    ('0065 0301', '00E9'),
    ('1100 1161 11A8', 'AC01'),
    ('212B', '00C5'),
  ];
}

String _fromCps(String cps) =>
    String.fromCharCodes(cps.split(' ').map((h) => int.parse(h, radix: 16)));

String _toCps(String s) => s.runes
    .map((r) => r.toRadixString(16).toUpperCase().padLeft(4, '0'))
    .join(' ');

void registerBackupCryptoTests() {
  test('the OS AES-GCM is in use (cryptography_flutter)', () {
    expect(AesGcm.with256bits(), isA<FlutterAesGcm>());
  });

  test('native NFC matches every shared row', () async {
    final n = PigeonTextNormalizer();
    for (final (input, want) in DeviceVector.nfcRows) {
      expect(_toCps(await n.nfc(_fromCps(input))), want, reason: input);
    }
  });

  test(
    'P, Argon2id, wrap, key ids and the whole file match the vectors',
    () async {
      final p = await PassphraseEncoder(PigeonTextNormalizer())
          .encode(DeviceVector.passphrase);
      expect(toHex(p), DeviceVector.pHex);

      final kdf = KdfParams.v1(hex(DeviceVector.saltHex));
      final sw = Stopwatch()..start();
      final kek = await const Argon2idKdf().derive(p, kdf);
      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('ZAGHLOL_KDF_MS=$ms (m=64MiB t=3 p=1, isolate)');
      expect(toHex(kek.bytes), DeviceVector.kekHex);

      final keys = await BackupKeySchedule(BackupPrimitives()).wrap(
        kbk: SecretBytes.copyOf(hex(DeviceVector.kbkHex)),
        kek: kek,
        kdf: kdf,
        wrapNonce: hex(DeviceVector.wrapNonceHex),
      );
      expect(toHex(keys.slot.wrappedKey), DeviceVector.wrapCtHex);
      expect(toHex(keys.slot.kbkId), DeviceVector.kbkIdHex);
      final fileId = hex(DeviceVector.fileIdHex);
      expect(
        toHex((await keys.chunkKey(fileId)).bytes),
        DeviceVector.kChunkHex,
      );
      expect(
        toHex((await keys.snapshotKey(fileId)).bytes),
        DeviceVector.kSnapHex,
      );

      final cipher = BackupCipher(
        secretStore: SlotSecretStore(),
        slotStore: MemorySlotStore(),
        normalizer: PigeonTextNormalizer(),
        random: ScriptedRandom([fileId, hex(DeviceVector.noncePrefixHex)]),
        clock: () => DateTime.fromMillisecondsSinceEpoch(
          DeviceVector.createdAtMs,
          isUtc: true,
        ),
      );
      final data = payload(DeviceVector.payloadLength);
      final file = await collect(
        cipher.encrypt(
          keys,
          HeaderMeta(
            seq: DeviceVector.seq,
            schemaVersion: DeviceVector.schemaVersion,
            platform: BackupPlatform.android,
            appVersion: DeviceVector.appVersion,
          ),
          streamOf(data),
          chunkSize: DeviceVector.chunkSize,
        ),
      );
      expect(sha256Hex(file), DeviceVector.fileSha256);

      // A precomposed, ASCII-digit spelling opens it through the native NFC.
      final session = await cipher.open(
        streamOf(file),
        'كلمة سر 345 أمان',
        maxSchemaVersion: 3,
      );
      expect(await collect(session.plaintext), data);
      (await session.done).keys.zeroize();
      keys.zeroize();
      wipe(p);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('a tampered chunk fails on the OS AES-GCM too', () async {
    final rig = Rig();
    final keys = await rig.cipher.createKey('device tamper pass');
    final file = await rig.write(keys, payload(2 * minChunkSize + 9));
    final bad = Uint8List.fromList(file)..[file.length - 20] ^= 1;
    final s = await rig.cipher.open(
      streamOf(bad),
      'device tamper pass',
      maxSchemaVersion: 3,
    );
    await expectLater(collect(s.plaintext), throwsA(anything));
    await expectLater(s.done, throwsA(anything));
  });
}
