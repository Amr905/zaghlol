// T-148 AC 2 and design note §4: passphrase normalization, and a wrong
// passphrase fails at the unwrap with wrongPassphrase before any chunk is
// read. The end-to-end cases use the real Argon2id (64 MiB, t = 3).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/passphrase.dart';
import 'package:zaghlol/features/backup/crypto/passphrase_kdf.dart';

import 'backup_test_support.dart';

/// Arabic with the Arabic-Indic digit ٣ and a precomposed أ.
const String arabicPass = 'زغلول ٣ أمان قوي';

/// The same with ASCII 3 and a decomposed hamza (alef + U+0654).
const String arabicPassVariant = 'زغلول 3 أمان قوي';

void main() {
  group('foldPassphrase / PassphraseEncoder (§4)', () {
    test('digits: Arabic-Indic and Extended to ASCII (provisional)', () {
      expect(foldPassphraseDigits, isTrue);
      expect(foldPassphrase('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(foldPassphrase('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      // Other scripts' digits are not folded (only the two Arabic sets).
      expect(foldPassphrase('०१२'), '०१२');
    });

    test('every Zs space separator becomes U+0020; nothing is trimmed', () {
      const zs = [
        0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, //
        0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000,
      ];
      for (final c in zs) {
        expect(foldPassphrase('a${String.fromCharCode(c)}b'), 'a b');
      }
      expect(foldPassphrase('  x  '), '  x  ');
      // Not Zs: tab, ZWSP, ZWNJ stay as they are.
      expect(foldPassphrase('a\tb​c‌d'), 'a\tb​c‌d');
    });

    test('no case folding', () {
      expect(foldPassphrase('PassWord'), 'PassWord');
    });

    test('NFC is asked only when a code point ≥ U+0300 is present', () async {
      final nfc = ArabicNfcFake();
      final enc = PassphraseEncoder(nfc);
      expect(await enc.normalize('plain ascii é ü'), 'plain ascii é ü');
      expect(nfc.calls, 0);
      expect(await enc.normalize('أ'), 'أ');
      expect(nfc.calls, 1);
    });

    test('a normalizer failure is io (no un-normalized fallback)', () async {
      final nfc = ArabicNfcFake()..fail = true;
      await expectLater(
        PassphraseEncoder(nfc).encode('كلمة سر طويلة'),
        throwsCode(BackupCryptoErrorCode.io),
      );
    });

    test('P is the UTF-8 of the normalized string', () async {
      final enc = PassphraseEncoder(ArabicNfcFake());
      final p = await enc.encode(arabicPassVariant);
      expect(p, utf8.encode('زغلول 3 أمان قوي'));
      expect(await enc.encode(arabicPass), p);
    });

    test(
      'minimum 8 code points after normalization, for new passphrases',
      () async {
        final enc = PassphraseEncoder(ArabicNfcFake());
        await expectLater(
          enc.encodeNew('1234567'),
          throwsCode(BackupCryptoErrorCode.passphraseTooShort),
        );
        // 7 letters + a decomposed hamza = 9 code points typed, 8 after NFC.
        expect(await enc.encodeNew('abcdefgأ'), isNotEmpty);
        // 6 letters + a decomposed hamza: 8 typed, 7 after NFC → refused.
        await expectLater(
          enc.encodeNew('abcdefأ'),
          throwsCode(BackupCryptoErrorCode.passphraseTooShort),
        );
        expect(await enc.encodeNew('12345678'), utf8.encode('12345678'));
      },
    );
  });

  group('AC 2: wrong passphrase (real Argon2id)', () {
    late Rig rig;
    late Uint8List file;
    late Uint8List data;

    setUpAll(() async {
      rig = Rig(kdf: const Argon2idKdf());
      final keys = await rig.cipher.createKey(arabicPass);
      data = payload(2 * minChunkSize + 77);
      file = await rig.write(keys, data);
      keys.zeroize();
    });

    Future<BackupCryptoErrorCode?> openWith(String p) async {
      final (block, chunks) = splitFile(file);
      final src = CountingSource(block, chunks);
      try {
        final s = await rig.cipher.open(src.stream, p, maxSchemaVersion: 3);
        final out = await collect(s.plaintext);
        expect(out, data);
        (await s.done).keys.zeroize();
        return null;
      } on BackupCryptoException catch (e) {
        expect(src.chunksPulled, 0, reason: 'no chunk read before unwrap');
        return e.reason;
      }
    }

    test('wrong passphrase → wrongPassphrase with zero chunks read', () async {
      expect(
        await openWith('something else entirely'),
        BackupCryptoErrorCode.wrongPassphrase,
      );
    });

    test('case change and a trailing space are wrong passphrases', () async {
      final rig2 = Rig(kdf: const Argon2idKdf());
      final k = await rig2.cipher.createKey('Zaghlol Pass');
      final f = await rig2.write(k, payload(10));
      for (final p in [
        'zaghlol pass',
        'ZAGHLOL PASS',
        'Zaghlol Pass ',
        ' Zaghlol Pass',
      ]) {
        await expectLater(
          rig2.cipher.open(streamOf(f), p, maxSchemaVersion: 3),
          throwsCode(BackupCryptoErrorCode.wrongPassphrase),
          reason: p,
        );
      }
      final ok = await rig2.cipher.open(
        streamOf(f),
        'Zaghlol Pass',
        maxSchemaVersion: 3,
      );
      await collect(ok.plaintext);
      (await ok.done).keys.zeroize();
    });

    test('٣ and 3 are the same passphrase; a decomposed hamza opens a file '
        'written with the precomposed one', () async {
      expect(await openWith(arabicPassVariant), isNull);
      expect(await openWith(arabicPass), isNull);
      expect(await openWith('زغلول ۳ أمان قوي'), isNull, reason: 'Extended ۳');
      expect(await openWith('زغلول 3 أمان قوي'), isNull, reason: 'NBSP');
    });

    test('newer schema is refused before the KDF (cheap refusal)', () async {
      final kdf = FastKdf();
      final rig3 = Rig(kdf: kdf);
      final k = await rig3.cipher.createKey('cheap refusal pass');
      final calls = kdf.calls;
      final f = await rig3.write(k, payload(5), schema: 9);
      await expectLater(
        rig3.cipher.open(
          streamOf(f),
          'cheap refusal pass',
          maxSchemaVersion: 8,
        ),
        throwsCode(BackupCryptoErrorCode.newerSchema),
      );
      expect(kdf.calls, calls, reason: 'KDF never ran');
      final s = await rig3.cipher.open(
        streamOf(f),
        'cheap refusal pass',
        maxSchemaVersion: 9,
      );
      await collect(s.plaintext);
      (await s.done).keys.zeroize();
    });

    test(
      'the real KDF refuses out-of-bounds parameters without running',
      () async {
        final big = KdfParams(
          salt: List.filled(16, 1),
          memoryKiB: 4 * 1024 * 1024,
          iterations: 3,
          parallelism: 1,
        );
        final sw = Stopwatch()..start();
        await expectLater(
          const Argon2idKdf().derive(Uint8List.fromList([1, 2, 3]), big),
          throwsCode(BackupCryptoErrorCode.unsupportedKdf),
        );
        expect(sw.elapsedMilliseconds, lessThan(50));
      },
    );
  });
}
