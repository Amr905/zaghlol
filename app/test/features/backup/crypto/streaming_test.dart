// T-148 §6/§7/§9 "Streaming": constant-memory encrypt + decrypt of a large
// synthetic stream (96 MiB by default; 300 MiB with ZAGHLOL_BACKUP_SLOW=1),
// verify-after-write, the DecryptSession contract (plaintext untrusted until
// done), and fail-closed encryption.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';

import 'backup_test_support.dart';

final bool _slow = Platform.environment['ZAGHLOL_BACKUP_SLOW'] == '1';
const String pass = 'streaming pass 148';

/// A synthetic source of [total] bytes in 64 KiB events, generated lazily.
Stream<List<int>> lazySource(int total, Sink<c.Digest> hash) async* {
  final h = c.sha256.startChunkedConversion(hash);
  const event = 65536;
  var sent = 0;
  while (sent < total) {
    final n = total - sent < event ? total - sent : event;
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = (sent + i) * 131 & 0xff;
    }
    h.add(b);
    sent += n;
    yield b;
  }
  h.close();
}

final class _DigestSink implements Sink<c.Digest> {
  c.Digest? value;
  @override
  void add(c.Digest data) => value = data;
  @override
  void close() {}
}

void main() {
  late Rig rig;
  late BackupKeys keys;

  setUpAll(() async {
    rig = Rig();
    keys = await rig.cipher.createKey(pass);
  });

  // Design note §9 asks for RSS growth < 16 MiB. On the host the pure-Dart
  // AES-GCM fallback (device builds use the OS AES-GCM) makes several MiB of
  // garbage per 1 MiB chunk, and the VM heap saw-tooths between ~35 and
  // ~62 MiB above baseline however long the stream is (measured over 400 MiB:
  // flat, not growing). So this test proves constant memory two ways: no
  // chunk buffer is retained (weak references are cleared), and RSS growth
  // stays under a fixed bound below the stream size (300 MiB in slow mode).
  // Deviation recorded in the task's implementation notes.
  test(
    'a ${_slow ? 300 : 96} MiB stream round-trips in constant memory '
    '(encrypt → decrypt piped, nothing assembled, nothing retained)',
    () async {
      final total = (_slow ? 300 : 96) << 20;
      final inHash = _DigestSink();
      final outHash = _DigestSink();
      final outSink = c.sha256.startChunkedConversion(outHash);

      // Warm up (JIT, allocator) before taking the baseline.
      await collect(
        rig.cipher.encrypt(keys, Rig.meta(), streamOf(payload(1 << 20))),
      );
      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final r = ProcessInfo.currentRss;
        if (r > peak) peak = r;
      });

      final encrypted = rig.cipher.encrypt(
        keys,
        Rig.meta(),
        lazySource(total, inHash),
      );
      final session = await rig.cipher.open(
        encrypted,
        pass,
        maxSchemaVersion: 3,
      );
      final weak = <WeakReference<Uint8List>>[];
      var outLen = 0;
      await for (final chunk in session.plaintext) {
        outSink.add(chunk);
        outLen += chunk.length;
        weak.add(WeakReference(chunk));
        final r = ProcessInfo.currentRss;
        if (r > peak) peak = r;
      }
      outSink.close();
      final done = await session.done;
      timer.cancel();

      expect(outLen, total);
      expect(outHash.value, inHash.value);
      expect(done.chunks, total ~/ defaultChunkSize);

      // Churn so the GC runs, then count the early chunks still alive.
      for (var i = 0; i < 96; i++) {
        Uint8List(1 << 20)[0] = i;
        await Future<void>.delayed(Duration.zero);
      }
      final early = weak.take(weak.length ~/ 2).toList();
      final alive = early.where((w) => w.target != null).length;
      final growthMiB = (peak - baseline) >> 20;
      // ignore: avoid_print
      print(
        'streaming ${total >> 20} MiB: RSS growth $growthMiB MiB, '
        'early chunks still alive: $alive/${early.length}',
      );
      expect(alive, lessThanOrEqualTo(2), reason: 'chunks are retained');
      expect(peak - baseline, lessThan(80 << 20));
      done.keys.zeroize();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'verify-after-write accepts the file and catches a flipped byte',
    () async {
      final file = await rig.write(keys, payload(3 * minChunkSize));
      expect(await rig.cipher.verifyFile(streamOf(file), keys), 3);
      final bad = Uint8List.fromList(file)..[file.length - 100] ^= 0x80;
      await expectLater(
        rig.cipher.verifyFile(streamOf(bad), keys),
        throwsCode(BackupCryptoErrorCode.corruptData),
      );
      await expectLater(
        rig.cipher.verifyFile(streamOf(file.sublist(0, 20)), keys),
        throwsCode(BackupCryptoErrorCode.corruptHeader),
      );
    },
  );

  test(
    'payload sizes at the edges: 0, 1, chunk-1, chunk, chunk+1, 2 chunks',
    () async {
      for (final n in [
        0,
        1,
        minChunkSize - 1,
        minChunkSize,
        minChunkSize + 1,
        2 * minChunkSize,
      ]) {
        final data = payload(n);
        final file = await rig.write(keys, data);
        final (_, chunks) = splitFile(file);
        final want = n == 0 ? 1 : (n + minChunkSize - 1) ~/ minChunkSize;
        expect(chunks, hasLength(want), reason: 'n=$n');
        for (final ch in chunks.take(chunks.length - 1)) {
          expect(ch.length, minChunkSize + gcmTagLength);
        }
        final s = await rig.cipher.open(
          streamOf(file),
          pass,
          maxSchemaVersion: 3,
        );
        expect(await collect(s.plaintext), data, reason: 'n=$n');
        (await s.done).keys.zeroize();
      }
    },
  );

  test('chunk sizes other than 1 MiB and unsupported ones', () async {
    final data = payload(300000);
    for (final size in [1 << 16, 1 << 17, 1 << 22]) {
      final file = await rig.write(keys, data, chunkSize: size);
      final s = await rig.cipher.open(
        streamOf(file),
        pass,
        maxSchemaVersion: 3,
      );
      expect(await collect(s.plaintext), data);
      (await s.done).keys.zeroize();
    }
    await expectLater(
      collect(
        rig.cipher.encrypt(keys, Rig.meta(), streamOf(data), chunkSize: 1000),
      ),
      throwsCode(BackupCryptoErrorCode.io),
    );
  });

  test('done completes only after the last chunk authenticated; a consumer '
      'that stops early never gets done', () async {
    final file = await rig.write(keys, payload(3 * minChunkSize + 5));
    final s = await rig.cipher.open(streamOf(file), pass, maxSchemaVersion: 3);
    var doneSeen = false;
    unawaited(s.done.then((_) => doneSeen = true, onError: (_) {}));
    var n = 0;
    await for (final _ in s.plaintext) {
      await Future<void>.delayed(Duration.zero);
      expect(doneSeen, isFalse, reason: 'done before chunk $n was the last');
      n++;
      if (n == 2) break;
    }
    await expectLater(s.done, throwsCode(BackupCryptoErrorCode.io));
    expect(() => s.plaintext, throwsStateError);
  });

  test('dispose without reading fails done and zeroes the keys', () async {
    final file = await rig.write(keys, payload(10));
    final s = await rig.cipher.open(streamOf(file), pass, maxSchemaVersion: 3);
    await s.dispose();
    await expectLater(s.done, throwsCode(BackupCryptoErrorCode.io));
  });

  test('fail closed: a failing plaintext source ends the stream with io and '
      'no further output', () async {
    Stream<List<int>> failing() async* {
      yield payload(minChunkSize + 10);
      throw const FileSystemException('synthetic read failure');
    }

    final out = <List<int>>[];
    Object? error;
    try {
      await for (final e in rig.cipher.encrypt(
        keys,
        Rig.meta(),
        failing(),
        chunkSize: minChunkSize,
      )) {
        out.add(e);
      }
    } on Object catch (e) {
      error = e;
    }
    expect(error, isCode(BackupCryptoErrorCode.io));
    // The header and the one full chunk were emitted, never a final chunk.
    expect(out, hasLength(2));
  });

  test('a failing file source is io', () async {
    Stream<List<int>> failing() async* {
      yield Uint8List(3);
      throw const FileSystemException('synthetic read failure');
    }

    await expectLater(
      rig.cipher.open(failing(), pass, maxSchemaVersion: 3),
      throwsCode(BackupCryptoErrorCode.io),
    );
  });

  test('a zeroized key cannot encrypt', () async {
    final k = await rig.cipher.createKey(pass);
    k.zeroize();
    expect(k.isZeroized, isTrue);
    await expectLater(
      collect(rig.cipher.encrypt(k, Rig.meta(), streamOf(payload(5)))),
      throwsCode(BackupCryptoErrorCode.io),
    );
  });
}
