// T-148 §8 / self-check §5: no key material, passphrase, header bytes or file
// id in any toString, exception or printed output. A full run (setup, write,
// open, every failure path) happens inside a zone that captures print; the
// sentinels must appear nowhere.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/pigeon_text_normalizer.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

import 'backup_test_support.dart';

const String sentinelPass = 'SENTINEL-PASSPHRASE-7f3a';

void main() {
  test('nothing secret reaches print, toString or an exception', () async {
    final printed = <String>[];
    final texts = <String>[];
    await runZoned(
      () async {
        final rig = Rig();
        final keys = await rig.cipher.createKey(sentinelPass);
        final kbkHex = toHex(keys.exportKey().bytes);
        final file = await rig.write(keys, payload(minChunkSize + 3));
        final (block, chunks) = splitFile(file);
        final fileIdHex = toHex(
          BackupHeader.decode(Uint8List.sublistView(block, 7)).fileId,
        );
        final session = await rig.cipher.open(
          streamOf(file),
          sentinelPass,
          maxSchemaVersion: 3,
        );
        final chunkKeyHex = toHex(
          (await keys.chunkKey(session.header.fileId)).bytes,
        );
        texts
          ..add('$keys')
          ..add('${keys.slot}')
          ..add('${keys.exportKey()}')
          ..add('${session.header}')
          ..add('$session');
        await collect(session.plaintext);
        final done = await session.done;
        texts.add('$done');

        Future<void> failing<T>(Future<T> Function() f) async {
          try {
            await f();
          } on Object catch (e, st) {
            texts
              ..add('$e')
              ..add('$st'.split('\n').first)
              ..add(e is BackupCryptoException ? e.code : '');
          }
        }

        await failing(
          () => rig.cipher.open(
            streamOf(file),
            'wrong $sentinelPass',
            maxSchemaVersion: 3,
          ),
        );
        final bad = Uint8List.fromList(file)..[file.length - 5] ^= 1;
        await failing<void>(() async {
          final s = await rig.cipher.open(
            streamOf(bad),
            sentinelPass,
            maxSchemaVersion: 3,
          );
          await collect(s.plaintext);
        });
        await failing(() => rig.cipher.verifyFile(streamOf(bad), keys));
        await failing(
          () => rig.cipher.open(
            streamOf(block),
            sentinelPass,
            maxSchemaVersion: 3,
          ),
        );
        await failing(() => rig.cipher.createKey('short'));
        rig.nfc.fail = true;
        await failing(
          () => rig.cipher.open(
            streamOf(file),
            'أ $sentinelPass',
            maxSchemaVersion: 3,
          ),
        );
        await failing(
          () => collect(
            rig.cipher.encrypt(
              keys,
              Rig.meta(),
              Stream.error(StateError(sentinelPass)),
            ),
          ),
        );
        await failing(() async => PigeonTextNormalizer().nfc(sentinelPass));
        await failing(
          () async => SecretBytes.copyOf([1])
            ..zeroize()
            ..bytes,
        );

        final secrets = [
          sentinelPass,
          kbkHex,
          chunkKeyHex,
          fileIdHex,
          toHex(chunks.first.sublist(0, 16)),
          toHex(block.sublist(7, 40)),
          base64.encode(keys.exportKey().bytes),
        ];
        final all = [...texts, ...printed].join('\n');
        for (final s in secrets) {
          expect(all.contains(s), isFalse, reason: 'leaked: a secret value');
        }
        expect(all.contains('SENTINEL'), isFalse);
        expect(printed, isEmpty, reason: 'the module prints nothing');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(texts, isNotEmpty);
  });

  test('the backup crypto sources contain no logging call', () {
    final dir = Directory('lib/features/backup/crypto');
    final pattern = RegExp(
      r'\b(print|debugPrint|log|developer\.log|dump)\(|\b(stdout|stderr)\b',
    );
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(pattern.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
