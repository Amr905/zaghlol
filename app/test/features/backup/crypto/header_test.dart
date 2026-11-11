// T-148 §7 steps 1–3 and §9 "Header" / "Fuzz": prefix dispatch, strict
// canonical CBOR, KDF bounds refused before the KDF runs, cheap refusals, and
// fixed-seed fuzzing of the decoder (slow mode: ZAGHLOL_BACKUP_SLOW=1, 10×).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/strict_cbor.dart';

import 'backup_test_support.dart';

final int _scale = Platform.environment['ZAGHLOL_BACKUP_SLOW'] == '1' ? 10 : 1;

KdfParams _kdf({int m = v1MemoryKiB, int t = 3, int p = 1}) => KdfParams(
  salt: List.generate(16, (i) => i + 1),
  memoryKiB: m,
  iterations: t,
  parallelism: p,
);

KeySlot _slot({KdfParams? kdf}) => KeySlot(
  kdf: kdf ?? _kdf(),
  wrapNonce: List.generate(12, (i) => 0x40 + i),
  wrappedKey: List.generate(48, (i) => 0x80 + i),
  kbkId: List.generate(16, (i) => 0xc0 + i),
);

BackupHeader _header({
  KdfParams? kdf,
  int chunkSize = defaultChunkSize,
  int schema = 3,
  int contents = 1,
}) => BackupHeader(
  slot: _slot(kdf: kdf),
  fileId: List.generate(16, (i) => 0x10 + i),
  noncePrefix: List.generate(8, (i) => 0x20 + i),
  chunkSize: chunkSize,
  createdAtMs: 1762848000123,
  meta: HeaderMeta(
    seq: 300,
    schemaVersion: schema,
    contentsVersion: contents,
    platform: BackupPlatform.ios,
    appVersion: '1.2.3+45',
  ),
);

/// The CBOR part of a block.
Uint8List _cbor(Uint8List block) => Uint8List.sublistView(block, 7);

/// Builds a header map by hand: [entries] are (key, encoded value).
Uint8List _map(List<(int, List<int>)> entries, {int? count}) {
  final w = CborWriter()..mapHeader(count ?? entries.length);
  final b = BytesBuilder()..add(w.takeBytes());
  for (final (k, v) in entries) {
    final kw = CborWriter()..uint(k);
    b
      ..add(kw.takeBytes())
      ..add(v);
  }
  return b.takeBytes();
}

Uint8List _u(int v) => (CborWriter()..uint(v)).takeBytes();
Uint8List _b(List<int> v) => (CborWriter()..bytes(v)).takeBytes();
Uint8List _t(String v) => (CborWriter()..text(v)).takeBytes();

/// The 12 canonical entries of [_header()], each value encoded.
List<(int, List<int>)> _entries() {
  final h = _header();
  final kdfMap = h.slot.kdf.toCbor();
  final wrap = _map([
    (1, _u(1)),
    (2, _b(h.slot.wrapNonce)),
    (3, _b(h.slot.wrappedKey)),
  ]);
  return [
    (1, kdfMap),
    (2, wrap),
    (3, _b(h.slot.kbkId)),
    (4, _b(h.fileId)),
    (5, _b(h.noncePrefix)),
    (6, _u(h.chunkSize)),
    (7, _u(h.createdAtMs)),
    (8, _u(300)),
    (9, _u(3)),
    (10, _u(1)),
    (11, _t('ios')),
    (12, _t('1.2.3+45')),
  ];
}

void main() {
  group('round trip', () {
    test('encode → decode gives the same header and the same bytes', () {
      final block = _header().encodeBlock();
      expect(block.sublist(0, 5), [0x5a, 0x47, 0x4c, 0x42, 1]);
      expect((block[5] << 8) | block[6], block.length - 7);
      final back = BackupHeader.decode(_cbor(block));
      expect(back.encodeBlock(), block);
      expect(back.meta.platform, BackupPlatform.ios);
      expect(back.meta.seq, 300);
      expect(back.slot.sameAs(_slot()), isTrue);
      // Hand-built canonical map is byte-identical to the encoder's output.
      expect(_map(_entries()), _cbor(block));
    });

    test('key slot round trip and strictness', () {
      final s = _slot();
      final cbor = s.toCbor();
      expect(KeySlot.fromCbor(cbor).sameAs(s), isTrue);
      expect(
        () => KeySlot.fromCbor(Uint8List.fromList([...cbor, 0])),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
      expect(
        () => KeySlot.fromCbor(Uint8List.sublistView(cbor, 0, cbor.length - 1)),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
      expect(
        () => KeySlot.fromCbor(_slot(kdf: _kdf(m: 1 << 22)).toCbor()),
        throwsCode(BackupCryptoErrorCode.unsupportedKdf),
      );
    });
  });

  group('prefix (step 1)', () {
    Uint8List p(List<int> b) => Uint8List.fromList(b);
    test('magic', () {
      expect(
        () => parsePrefix(p([])),
        throwsCode(BackupCryptoErrorCode.notABackup),
      );
      expect(
        () => parsePrefix(p([0x5a, 0x47])),
        throwsCode(BackupCryptoErrorCode.notABackup),
      );
      expect(
        () => parsePrefix(p([0x50, 0x4b, 3, 4, 1, 0, 9])),
        throwsCode(BackupCryptoErrorCode.notABackup),
      );
      expect(
        () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42])),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
    });
    test('version', () {
      expect(
        () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 2, 0, 9])),
        throwsCode(BackupCryptoErrorCode.newerFormat),
      );
      expect(
        () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 0xff])),
        throwsCode(BackupCryptoErrorCode.newerFormat),
      );
      expect(
        () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 0, 0, 9])),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
    });
    test('headerLen 1..4096', () {
      expect(parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 1, 0, 1])), 1);
      expect(parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 1, 0x10, 0])), 4096);
      for (final bad in [
        [0, 0],
        [0x10, 1],
        [0xff, 0xff],
      ]) {
        expect(
          () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 1, ...bad])),
          throwsCode(BackupCryptoErrorCode.corruptHeader),
        );
      }
      expect(
        () => parsePrefix(p([0x5a, 0x47, 0x4c, 0x42, 1, 0])),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
    });
  });

  group('strict CBOR (step 2) → corruptHeader', () {
    void corrupt(List<int> bytes, String why) => expect(
      () => BackupHeader.decode(Uint8List.fromList(bytes)),
      throwsCode(BackupCryptoErrorCode.corruptHeader),
      reason: why,
    );

    test('long-form integer (seq 300 as 4 bytes)', () {
      final e = _entries();
      e[7] = (8, [0x1a, 0, 0, 1, 0x2c]);
      corrupt(_map(e), 'non-shortest uint');
      e[7] = (8, [0x18, 5]);
      corrupt(_map(e), '5 encoded in one extra byte');
    });

    test('long-form key, long-form length', () {
      final good = _map(_entries());
      // Key 4 written as 0x18 0x04.
      final e = _entries();
      final b = BytesBuilder()..add(_map(e.sublist(0, 3), count: 12));
      b
        ..add([0x18, 4])
        ..add(e[3].$2);
      for (final x in e.sublist(4)) {
        b
          ..add(_u(x.$1))
          ..add(x.$2);
      }
      corrupt(b.takeBytes(), 'long-form key');
      // fileId with a 1-byte length head (0x58 0x10).
      final e2 = _entries();
      e2[3] = (4, [0x58, 16, ...List.generate(16, (i) => 0x10 + i)]);
      corrupt(_map(e2), 'long-form bstr length');
      expect(BackupHeader.decode(good).meta.seq, 300);
    });

    test('reordered keys, duplicate key, unknown key 13, missing key', () {
      final e = _entries();
      final swapped = [...e]
        ..[3] = e[4]
        ..[4] = e[3];
      corrupt(_map(swapped), 'keys 4 and 5 swapped');
      final dup = [...e]..[4] = (4, e[4].$2);
      corrupt(_map(dup), 'duplicate key 4');
      corrupt(_map([...e, (13, _u(1))]), 'unknown key 13');
      corrupt(_map(e.sublist(0, 11)), 'missing key 12');
      corrupt(_map(e, count: 13), 'count says 13');
    });

    test('wrong types and lengths', () {
      final e = _entries();
      corrupt(_map([...e]..[3] = (4, _b(List.filled(15, 1)))), 'fileId 15');
      corrupt(_map([...e]..[4] = (5, _b(List.filled(9, 1)))), 'prefix 9');
      corrupt(_map([...e]..[2] = (3, _u(5))), 'kbkId as uint');
      corrupt(_map([...e]..[6] = (7, _b([1]))), 'createdAt as bstr');
      corrupt(_map([...e]..[10] = (11, _t('web'))), 'platform web');
      corrupt(_map([...e]..[10] = (11, _b([0x69, 0x6f, 0x73]))), 'bstr ios');
      corrupt(_map([...e]..[11] = (12, _t(''))), 'empty appVersion');
      corrupt(_map([...e]..[11] = (12, _t('x' * 33))), 'appVersion 33');
      corrupt(_map([...e]..[11] = (12, _t('1.0\n'))), 'control char');
      corrupt(_map([...e]..[11] = (12, [0x62, 0xc3, 0x28])), 'bad UTF-8');
      corrupt(_map([...e]..[9] = (10, _u(0))), 'contentsVersion 0');
      corrupt(_map([...e]..[5] = (6, _u(65535))), 'chunk not a power of 2');
      corrupt(_map([...e]..[5] = (6, _u(32768))), 'chunk too small');
      corrupt(_map([...e]..[5] = (6, _u(1 << 23))), 'chunk too large');
      corrupt(_map([...e]..[7] = (8, [0x20])), 'negative integer');
      corrupt(_map([...e]..[7] = (8, [0xf9, 0, 0])), 'half float');
      corrupt(_map([...e]..[7] = (8, [0xc1, 0x01])), 'tag');
      corrupt(_map([...e]..[7] = (8, [0xf5])), 'simple true');
      corrupt(_map([...e]..[3] = (4, [0x5f, 0xff])), 'indefinite bstr');
      corrupt(_map([...e]..[7] = (8, [0x1c])), 'reserved info 28');
      corrupt(
        _map([...e]..[7] = (8, [0x1b, 0x80, 0, 0, 0, 0, 0, 0, 0])),
        'uint64 ≥ 2^63',
      );
      corrupt([0xbf, ..._map(e).sublist(1), 0xff], 'indefinite map');
      corrupt([0x80], 'array');
      corrupt([], 'empty');
    });

    test('wrap shape and algorithm', () {
      final e = _entries();
      final h = _header();
      Uint8List wrap(List<(int, List<int>)> w) => _map(w);
      corrupt(
        _map(
          [...e]
            ..[1] = (
              2,
              wrap([
                (1, _u(2)),
                (2, _b(h.slot.wrapNonce)),
                (3, _b(h.slot.wrappedKey)),
              ]),
            ),
        ),
        'wrap alg 2',
      );
      corrupt(
        _map(
          [...e]
            ..[1] = (
              2,
              wrap([
                (1, _u(1)),
                (2, _b(h.slot.wrapNonce)),
                (3, _b(List.filled(47, 0))),
              ]),
            ),
        ),
        'wrap ct 47',
      );
    });

    test('trailing bytes after the map', () {
      corrupt([..._map(_entries()), 0x00], 'one trailing byte');
    });
  });

  group('KDF bounds → unsupportedKdf (refused before any KDF)', () {
    void unsupported(KdfParams kdf, String why) {
      final cbor = _cbor(_header(kdf: kdf).encodeBlock());
      expect(
        () => BackupHeader.decode(cbor),
        throwsCode(BackupCryptoErrorCode.unsupportedKdf),
        reason: why,
      );
    }

    test('memory, iterations, parallelism', () {
      unsupported(_kdf(m: 4 * 1024 * 1024), 'm = 4 GiB');
      unsupported(_kdf(m: 19455), 'm below 19 MiB');
      unsupported(_kdf(m: 262145), 'm above 256 MiB');
      unsupported(_kdf(t: 0), 't = 0');
      unsupported(_kdf(t: 11), 't = 11');
      unsupported(_kdf(p: 0), 'p = 0');
      unsupported(_kdf(p: 5), 'p = 5');
      for (final ok in [
        _kdf(m: 19456, t: 1, p: 1),
        _kdf(m: 262144, t: 10, p: 4),
      ]) {
        expect(
          BackupHeader.decode(_cbor(_header(kdf: ok).encodeBlock())),
          isNotNull,
        );
      }
    });

    test('algorithm other than argon2id', () {
      final e = _entries();
      final kdf = _map([
        (1, _u(2)),
        (2, _b(List.generate(16, (i) => i + 1))),
        (3, _u(v1MemoryKiB)),
        (4, _u(3)),
        (5, _u(1)),
      ]);
      expect(
        () => BackupHeader.decode(_map([...e]..[0] = (1, kdf))),
        throwsCode(BackupCryptoErrorCode.unsupportedKdf),
      );
    });

    test('a shape error wins over a bounds error', () {
      final e = _entries();
      final kdf = _map([
        (1, _u(1)),
        (2, _b(List.generate(16, (i) => i + 1))),
        (3, _u(4 * 1024 * 1024)),
        (4, _u(3)),
        (5, _u(1)),
      ]);
      expect(
        () => BackupHeader.decode(_map([...e]..[0] = (1, kdf), count: 11)),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
    });
  });

  group('fuzz (fixed seed)', () {
    bool typed(Object e) =>
        e is BackupCryptoException &&
        (e.reason == BackupCryptoErrorCode.corruptHeader ||
            e.reason == BackupCryptoErrorCode.unsupportedKdf);

    test('${10000 * _scale} random byte strings: only corruptHeader or '
        'unsupportedKdf', () {
      final rng = Random(148);
      for (var n = 0; n < 10000 * _scale; n++) {
        final len = rng.nextInt(400);
        final bytes = Uint8List.fromList(
          List.generate(len, (_) => rng.nextInt(256)),
        );
        // A plausible start half of the time, so parsing gets deep.
        if (len > 0 && rng.nextBool()) bytes[0] = 0xac;
        try {
          BackupHeader.decode(bytes);
        } on Object catch (e) {
          expect(typed(e), isTrue, reason: 'case $n threw ${e.runtimeType}');
        }
      }
    });

    test('${10000 * _scale} mutations of a valid header', () {
      final rng = Random(9106);
      final good = _cbor(_header().encodeBlock());
      var accepted = 0;
      for (var n = 0; n < 10000 * _scale; n++) {
        final m = Uint8List.fromList(good);
        final kind = rng.nextInt(4);
        Uint8List input;
        switch (kind) {
          case 0:
            m[rng.nextInt(m.length)] ^= 1 << rng.nextInt(8);
            input = m;
          case 1:
            m[rng.nextInt(m.length)] = rng.nextInt(256);
            input = m;
          case 2:
            input = Uint8List.sublistView(m, 0, rng.nextInt(m.length));
          default:
            final at = rng.nextInt(m.length);
            input = Uint8List.fromList([
              ...m.sublist(0, at),
              rng.nextInt(256),
              ...m.sublist(at),
            ]);
        }
        try {
          final h = BackupHeader.decode(input);
          accepted++;
          // Anything accepted re-encodes to exactly the input (canonical).
          expect(_cbor(h.encodeBlock()), input, reason: 'case $n');
        } on Object catch (e) {
          expect(typed(e), isTrue, reason: 'case $n threw ${e.runtimeType}');
        }
      }
      expect(accepted, greaterThan(0));
    });
  });
}
