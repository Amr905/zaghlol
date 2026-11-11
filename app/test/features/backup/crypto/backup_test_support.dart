// T-148: fakes and helpers for the backup crypto tests. Everything is
// synthetic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/features/backup/crypto/backup_cipher.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/passphrase.dart';
import 'package:zaghlol/features/backup/crypto/passphrase_kdf.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String sha256Hex(List<int> b) => c.sha256.convert(b).toString();

/// byte[i] = (i * 131 + (i >> 8)) & 0xff (same formula as the Python
/// generator).
Uint8List payload(int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = ((i * 131) + (i >> 8)) & 0xff;
  }
  return out;
}

/// Emits [bytes] in events of [eventSize] bytes.
Stream<List<int>> streamOf(List<int> bytes, {int eventSize = 4096}) async* {
  for (var i = 0; i < bytes.length; i += eventSize) {
    final end = i + eventSize < bytes.length ? i + eventSize : bytes.length;
    yield Uint8List.fromList(bytes.sublist(i, end));
  }
}

Future<Uint8List> collect(Stream<List<int>> s) async {
  final b = BytesBuilder(copy: false);
  await for (final e in s) {
    b.add(e);
  }
  return b.takeBytes();
}

Map<String, Object?> loadVectors() => jsonDecode(
  File('test/fixtures/backup/zglb-v1-vectors.json').readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> vectorCases() =>
    (loadVectors()['cases']! as List).cast<Map<String, Object?>>();

/// Matches a BackupCryptoException with [code].
Matcher throwsCode(BackupCryptoErrorCode code) => throwsA(isCode(code));

Matcher isCode(BackupCryptoErrorCode code) =>
    isA<BackupCryptoException>().having((e) => e.reason, 'reason', code);

/// The Arabic canonical compositions (and the kasra/shadda reorder used in
/// the vectors). Host tests have no platform normalizer; device legs use the
/// real one. Counts calls.
final class ArabicNfcFake implements TextNormalizer {
  int calls = 0;
  bool fail = false;

  static const Map<String, String> _pairs = {
    'آ': 'آ',
    'أ': 'أ',
    'ؤ': 'ؤ',
    'إ': 'إ',
    'ئ': 'ئ',
    'ۀ': 'ۀ',
    'ۂ': 'ۂ',
    'ۓ': 'ۓ',
    'ِّ': 'ِّ',
  };

  @override
  Future<String> nfc(String input) async {
    calls++;
    if (fail) throw StateError('platform channel down');
    var s = input;
    _pairs.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }
}

/// A fast, parameter-sensitive stand-in for Argon2id: HMAC-SHA256 over the
/// password keyed by salt ‖ m ‖ t ‖ p. Enforces the same bounds and records
/// every call, so tests can prove "refused before the KDF ran".
base class FastKdf implements PassphraseKdf {
  int calls = 0;
  final List<int> memoryRequested = [];

  @override
  Future<SecretBytes> derive(Uint8List password, KdfParams params) async {
    if (!params.withinBounds) {
      throw BackupCryptoException(BackupCryptoErrorCode.unsupportedKdf);
    }
    calls++;
    memoryRequested.add(params.memoryKiB);
    final key = [
      ...params.salt,
      ...utf8.encode(
        '${params.memoryKiB}/${params.iterations}/${params.parallelism}',
      ),
    ];
    return SecretBytes.copyOf(c.Hmac(c.sha256, key).convert(password).bytes);
  }
}

/// Returns queued byte arrays (by request), then falls back to a counter.
final class ScriptedRandom implements BackupRandom {
  ScriptedRandom([List<List<int>>? queue]) : _queue = [...?queue];

  final List<List<int>> _queue;
  int _counter = 1;

  void push(List<int> bytes) => _queue.add(bytes);

  @override
  Uint8List bytes(int length) {
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (next.length != length) {
        throw StateError('scripted random: wanted $length got ${next.length}');
      }
      return Uint8List.fromList(next);
    }
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = (_counter * 37 + i * 11) & 0xff;
    }
    _counter++;
    return out;
  }
}

/// In-memory key slot store.
final class MemorySlotStore implements BackupKeySlotStore {
  Uint8List? stored;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;

  /// Called right before a write lands (to simulate a crash: throw).
  void Function()? beforeWrite;

  @override
  Future<Uint8List?> read() async {
    if (failRead) throw StateError('db locked');
    final s = stored;
    return s == null ? null : Uint8List.fromList(s);
  }

  @override
  Future<void> write(Uint8List slotCbor) async {
    beforeWrite?.call();
    if (failWrite) throw StateError('db full');
    writes++;
    stored = Uint8List.fromList(slotCbor);
  }
}

/// A per-slot SecretStore with the native semantics that matter here: one
/// process-wide lease (writes need it), createIfAbsent winner semantics,
/// delete idempotent, forced read statuses. Records calls per slot.
final class SlotSecretStore implements SecretStore {
  final Map<SecretSlot, Uint8List> values = {};
  final Map<SecretSlot, SecretStatus> forced = {};
  final List<String> calls = [];
  SecretStoreErrorCode? failAcquire;
  SecretStoreErrorCode? failCreate;
  bool renewFails = false;

  int? _held;
  int _next = 1;
  final List<Completer<void>> _waiters = [];

  int writesTo(SecretSlot slot) => calls
      .where((c) => c == 'create:${slot.name}' || c == 'delete:${slot.name}')
      .length;

  @override
  Future<SecretStoreLease> acquireBootstrapLease(Duration timeout) async {
    calls.add('acquire');
    final f = failAcquire;
    if (f != null) throw SecretStoreException(f);
    final deadline = DateTime.now().add(timeout);
    while (_held != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
      }
      final w = Completer<void>();
      _waiters.add(w);
      try {
        await w.future.timeout(remaining);
      } on TimeoutException {
        _waiters.remove(w);
        throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
      }
    }
    _held = _next++;
    return SecretStoreLease(_held!);
  }

  @override
  Future<void> releaseBootstrapLease(SecretStoreLease lease) async {
    calls.add('release');
    if (_held == lease.id) {
      _held = null;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  @override
  Future<bool> renewBootstrapLease(SecretStoreLease lease) async {
    calls.add('renew');
    if (renewFails) return false;
    return _held == lease.id;
  }

  void _requireLease(SecretStoreLease lease) {
    if (_held != lease.id) {
      throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
    }
  }

  @override
  Future<SecretRead> read(SecretSlot slot) async {
    calls.add('read:${slot.name}');
    // Let other actors interleave, like a platform channel round trip.
    await Future<void>.delayed(Duration.zero);
    final f = forced[slot];
    if (f != null && f != SecretStatus.found) return SecretRead(f);
    final v = values[slot];
    if (v == null) return SecretRead(SecretStatus.notFound);
    return SecretRead(SecretStatus.found, value: Uint8List.fromList(v));
  }

  @override
  Future<Uint8List> createIfAbsent(
    SecretStoreLease lease,
    SecretSlot slot,
    Uint8List candidate,
  ) async {
    calls.add('create:${slot.name}');
    await Future<void>.delayed(Duration.zero);
    _requireLease(lease);
    final f = failCreate;
    if (f != null) throw SecretStoreException(f);
    final status = forced[slot];
    if (status == SecretStatus.unusable || status == SecretStatus.unavailable) {
      throw const SecretStoreException(SecretStoreErrorCode.storeFailed);
    }
    final existing = values[slot];
    if (existing != null) return Uint8List.fromList(existing);
    values[slot] = Uint8List.fromList(candidate);
    return Uint8List.fromList(candidate);
  }

  @override
  Future<void> delete(SecretStoreLease lease, SecretSlot slot) async {
    calls.add('delete:${slot.name}');
    await Future<void>.delayed(Duration.zero);
    _requireLease(lease);
    values.remove(slot);
    forced.remove(slot);
  }
}

/// A source that yields [prefixAndHeader] as one event and then each of
/// [chunks] as its own event, counting how many chunk events were pulled.
final class CountingSource {
  CountingSource(this.prefixAndHeader, this.chunks);

  final List<int> prefixAndHeader;
  final List<List<int>> chunks;
  int chunksPulled = 0;

  Stream<List<int>> get stream async* {
    yield prefixAndHeader;
    for (final ch in chunks) {
      chunksPulled++;
      yield ch;
    }
  }
}

/// Splits a v1 file into (headerBlock, chunks) using its header.
(Uint8List, List<Uint8List>) splitFile(Uint8List file) {
  final headerLen = (file[5] << 8) | file[6];
  final blockLen = backupPrefixLength + headerLen;
  final header = BackupHeader.decode(
    Uint8List.sublistView(file, backupPrefixLength, blockLen),
  );
  final sealed = header.chunkSize + gcmTagLength;
  final chunks = <Uint8List>[];
  for (var o = blockLen; o < file.length; o += sealed) {
    final end = o + sealed < file.length ? o + sealed : file.length;
    chunks.add(Uint8List.fromList(file.sublist(o, end)));
  }
  return (Uint8List.fromList(file.sublist(0, blockLen)), chunks);
}

Uint8List join(Uint8List block, List<List<int>> chunks) {
  final b = BytesBuilder(copy: true)..add(block);
  for (final ch in chunks) {
    b.add(ch);
  }
  return b.takeBytes();
}

/// A test cipher with the fast KDF, the Arabic NFC fake and in-memory stores.
final class Rig {
  Rig({PassphraseKdf? kdf, BackupRandom? random, DateTime Function()? clock})
    : kdf = kdf ?? FastKdf(),
      random = random ?? ScriptedRandom() {
    cipher = BackupCipher(
      secretStore: store,
      slotStore: slots,
      normalizer: nfc,
      kdf: this.kdf,
      random: this.random,
      clock: clock ?? () => DateTime.utc(2026, 11, 11, 9),
      leaseTimeout: const Duration(milliseconds: 200),
    );
  }

  final SlotSecretStore store = SlotSecretStore();
  final MemorySlotStore slots = MemorySlotStore();
  final ArabicNfcFake nfc = ArabicNfcFake();
  final PassphraseKdf kdf;
  final BackupRandom random;
  late final BackupCipher cipher;

  static HeaderMeta meta({int schema = 3, int seq = 1}) => HeaderMeta(
    seq: seq,
    schemaVersion: schema,
    platform: BackupPlatform.android,
    appVersion: '0.1.0+1',
  );

  /// Encrypts [data] into a file held in memory.
  Future<Uint8List> write(
    BackupKeys keys,
    List<int> data, {
    int chunkSize = minChunkSize,
    int schema = 3,
  }) => collect(
    cipher.encrypt(
      keys,
      meta(schema: schema),
      streamOf(data, eventSize: 10007),
      chunkSize: chunkSize,
    ),
  );
}
