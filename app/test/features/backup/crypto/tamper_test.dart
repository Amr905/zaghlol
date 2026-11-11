// T-148 AC 1 (design note §9): truncated, reordered, duplicated, swapped and
// flipped chunks fail with corruptData, and the consumer never sees `done`.
// Also: every header byte flipped gives only typed errors, and fixed-seed
// fuzzing of whole files (slow mode: ZAGHLOL_BACKUP_SLOW=1, 10×).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/backup_primitives.dart';
import 'package:zaghlol/features/backup/crypto/backup_stream.dart';
import 'package:zaghlol/features/backup/crypto/byte_reader.dart';

import 'backup_test_support.dart';

final int _scale = Platform.environment['ZAGHLOL_BACKUP_SLOW'] == '1' ? 10 : 1;

const String pass = 'synthetic pass 148';

/// What a consumer observes: the plaintext it got, whether `done` completed
/// successfully, and the error code if any.
final class Outcome {
  Outcome(this.plaintext, this.done, this.error);
  final Uint8List plaintext;
  final bool done;
  final BackupCryptoErrorCode? error;
}

Future<Outcome> consume(Rig rig, List<int> file, {int eventSize = 7919}) async {
  final out = BytesBuilder();
  try {
    final session = await rig.cipher.open(
      streamOf(file, eventSize: eventSize),
      pass,
      maxSchemaVersion: 3,
    );
    var done = false;
    BackupCryptoErrorCode? err;
    try {
      await for (final c in session.plaintext) {
        out.add(c);
      }
    } on BackupCryptoException catch (e) {
      err = e.reason;
    }
    try {
      final r = await session.done;
      done = true;
      r.keys.zeroize();
    } on BackupCryptoException catch (e) {
      err ??= e.reason;
    }
    return Outcome(out.takeBytes(), done, err);
  } on BackupCryptoException catch (e) {
    return Outcome(out.takeBytes(), false, e.reason);
  }
}

void main() {
  late Rig rig;
  late BackupKeys keys;
  late Uint8List data;
  late Uint8List file;
  late Uint8List block;
  late List<Uint8List> chunks;
  late Uint8List other;
  late List<Uint8List> otherChunks;

  setUpAll(() async {
    rig = Rig();
    keys = await rig.cipher.createKey(pass);
    // 4 chunks at 64 KiB: three full ones and a short last one.
    data = payload(3 * minChunkSize + 1234);
    file = await rig.write(keys, data);
    (block, chunks) = splitFile(file);
    // A second file under the same K_bk (another fileId / noncePrefix).
    other = await rig.write(keys, data);
    final (_, oc) = splitFile(other);
    otherChunks = oc;
  });

  Future<void> expectCorrupt(List<int> f, String why) async {
    final o = await consume(rig, f);
    expect(o.error, BackupCryptoErrorCode.corruptData, reason: why);
    expect(o.done, isFalse, reason: '$why: done must not complete');
  }

  test('the intact file decrypts and completes', () async {
    expect(chunks, hasLength(4));
    expect(chunks.last.length, 1234 + gcmTagLength);
    final o = await consume(rig, file);
    expect(o.error, isNull);
    expect(o.done, isTrue);
    expect(o.plaintext, data);
  });

  test('truncation at every chunk boundary and ±1 byte of each', () async {
    var cases = 0;
    var offset = block.length;
    for (var i = 0; i < chunks.length; i++) {
      // Boundary before chunk i (i == 0: header only, no chunk at all).
      for (final d in [-1, 0, 1]) {
        final cut = offset + d;
        if (cut <= block.length - 1) continue; // header cuts: see below
        await expectCorrupt(file.sublist(0, cut), 'cut at $cut (chunk $i, $d)');
        cases++;
      }
      offset += chunks[i].length;
    }
    // One byte short of the full file.
    await expectCorrupt(file.sublist(0, file.length - 1), 'last byte cut');
    expect(cases, greaterThanOrEqualTo(10));
  });

  test('truncation inside the header is corruptHeader', () async {
    for (final cut in [0, 3, 6, 7, block.length - 1]) {
      final o = await consume(rig, file.sublist(0, cut));
      expect(
        o.error,
        cut < 4
            ? BackupCryptoErrorCode.notABackup
            : BackupCryptoErrorCode.corruptHeader,
        reason: 'cut $cut',
      );
      expect(o.done, isFalse);
    }
  });

  test('drop, swap, duplicate, append', () async {
    await expectCorrupt(
      join(block, [chunks[0], chunks[2], chunks[3]]),
      'drop 1',
    );
    await expectCorrupt(
      join(block, [chunks[0], chunks[2], chunks[1], chunks[3]]),
      'swap 1 and 2',
    );
    await expectCorrupt(
      join(block, [chunks[0], chunks[1], chunks[2], chunks[2], chunks[3]]),
      'duplicate 2',
    );
    await expectCorrupt(
      join(block, [...chunks.sublist(0, 3)]),
      'final chunk missing',
    );
    await expectCorrupt(
      join(block, [...chunks.sublist(0, 2)]),
      'last two missing',
    );
    await expectCorrupt([...file, 0], 'one byte appended');
    await expectCorrupt(
      join(block, [...chunks, otherChunks[3]]),
      'a chunk of another file appended',
    );
    await expectCorrupt(
      join(block, [chunks[0], chunks[1], otherChunks[2], chunks[3]]),
      'chunk 2 replaced by chunk 2 of another file (same K_bk)',
    );
    await expectCorrupt(join(block, const []), 'no chunk at all');
  });

  test('another file\'s header with this file\'s chunks', () async {
    final (otherBlock, _) = splitFile(other);
    await expectCorrupt(join(otherBlock, chunks), 'header swap');
  });

  test('a repeated noncePrefix across two files under the same K_bk does not '
      'reuse the keystream (per-file K_chunk = HKDF(K_bk, fileId))', () async {
    final prefix = List.filled(noncePrefixLength, 0x33);
    final random = ScriptedRandom();
    final r = Rig(random: random);
    // createKey takes salt, K_bk and wrap nonce from the counter fallback.
    final k = await r.cipher.createKey(pass);
    random
      ..push(List.filled(fileIdLength, 0x01))
      ..push(prefix)
      ..push(List.filled(fileIdLength, 0x02))
      ..push(prefix);
    final data = payload(minChunkSize);
    final a = await r.write(k, data);
    final b = await r.write(k, data);
    final (_, ca) = splitFile(a);
    final (_, cb) = splitFile(b);
    final bodyA = ca.first.sublist(0, 64);
    final bodyB = cb.first.sublist(0, 64);
    expect(bodyA, isNot(equals(bodyB)), reason: 'same keystream reused');
  });

  test('one byte flipped in each chunk body and each tag', () async {
    var offset = block.length;
    for (var i = 0; i < chunks.length; i++) {
      for (final at in [0, chunks[i].length ~/ 2, chunks[i].length - 1]) {
        final f = Uint8List.fromList(file);
        f[offset + at] ^= 0x01;
        await expectCorrupt(f, 'chunk $i byte $at');
      }
      offset += chunks[i].length;
    }
  });

  test('every header byte flipped: only typed errors, never done', () async {
    const allowed = {
      BackupCryptoErrorCode.notABackup,
      BackupCryptoErrorCode.newerFormat,
      BackupCryptoErrorCode.corruptHeader,
      BackupCryptoErrorCode.unsupportedKdf,
      BackupCryptoErrorCode.newerSchema,
      BackupCryptoErrorCode.wrongPassphrase,
      BackupCryptoErrorCode.corruptData,
    };
    final seen = <BackupCryptoErrorCode>{};
    for (var i = 0; i < block.length; i++) {
      final f = Uint8List.fromList(file);
      f[i] ^= 0x01;
      final o = await consume(rig, f);
      expect(o.done, isFalse, reason: 'header byte $i');
      expect(allowed, contains(o.error), reason: 'header byte $i: ${o.error}');
      seen.add(o.error!);
    }
    // Each class of field was hit: prefix, CBOR shape, KDF, wrap, AAD-only.
    expect(
      seen,
      containsAll([
        BackupCryptoErrorCode.notABackup,
        BackupCryptoErrorCode.corruptHeader,
        BackupCryptoErrorCode.wrongPassphrase,
        BackupCryptoErrorCode.corruptData,
      ]),
    );
  });

  test(
    'a chunk shorter than a tag, and an empty chunk after chunk 0',
    () async {
      await expectCorrupt(join(block, [chunks[0].sublist(0, 15)]), '15 bytes');
      // Exactly a tag is allowed only as chunk 0 of an empty payload.
      final emptyFile = await rig.write(keys, const []);
      final (eb, ec) = splitFile(emptyFile);
      expect(ec.single.length, gcmTagLength);
      final ok = await consume(rig, emptyFile);
      expect(ok.done, isTrue);
      expect(ok.plaintext, isEmpty);
      await expectCorrupt(join(eb, [ec.single, ec.single]), 'empty twice');
    },
  );

  test('event sizes do not matter (1 byte to whole file)', () async {
    for (final size in [1, 17, minChunkSize + gcmTagLength, file.length]) {
      if (size == 1) {
        // 1-byte events over 200 KiB is slow; use the first 2 chunks only.
        final small = await rig.write(keys, payload(minChunkSize + 10));
        final o = await consume(rig, small, eventSize: 1);
        expect(o.done, isTrue);
        continue;
      }
      final o = await consume(rig, file, eventSize: size);
      expect(o.done, isTrue, reason: 'event size $size');
      expect(o.plaintext, data);
    }
  });

  test('the chunk-count limit refuses on both sides', () async {
    final primitives = BackupPrimitives();
    final (b, h) = await readHeader(ByteReader(streamOf(file)));
    final k = await keys.chunkKey(h.fileId);
    // Reader: 4 chunks against a limit of 3.
    final reader = ByteReader(streamOf(file));
    await readHeader(reader);
    await expectLater(
      decryptChunks(
        primitives: primitives,
        chunkKey: k,
        headerBlock: b,
        header: h,
        reader: reader,
        chunkLimit: 3,
      ).drain<void>(),
      throwsCode(BackupCryptoErrorCode.corruptData),
    );
    // Writer: refuses to start chunk 3 with a limit of 3.
    await expectLater(
      encryptStream(
        primitives: primitives,
        keys: keys,
        header: h,
        plaintext: streamOf(data),
        chunkLimit: 3,
      ).drain<void>(),
      throwsCode(BackupCryptoErrorCode.io),
    );
  });

  group('fuzz (fixed seed)', () {
    late Uint8List small;
    setUpAll(() async {
      small = await rig.write(keys, payload(minChunkSize + 300));
    });

    test('${2000 * _scale} random truncations: typed errors only', () async {
      final rng = Random(5869);
      for (var n = 0; n < 2000 * _scale; n++) {
        final cut = rng.nextInt(small.length);
        final o = await consume(rig, small.sublist(0, cut));
        expect(o.done, isFalse, reason: 'cut $cut');
        expect(o.error, isNotNull, reason: 'cut $cut');
      }
    });

    test('${2000 * _scale} random byte flips: typed errors only', () async {
      final rng = Random(8949);
      for (var n = 0; n < 2000 * _scale; n++) {
        final f = Uint8List.fromList(small);
        final at = rng.nextInt(f.length);
        f[at] ^= 1 + rng.nextInt(255);
        final o = await consume(rig, f);
        expect(o.done, isFalse, reason: 'flip at $at');
        expect(o.error, isNotNull, reason: 'flip at $at');
      }
    });
  });
}
