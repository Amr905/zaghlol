// T-148: backup file format v1 (design note §2; security-model §5).
//
//   file   = prefix ‖ header ‖ chunk_0 ‖ … ‖ chunk_{n-1}
//   prefix = "ZGLB" ‖ formatVersion u8 = 1 ‖ headerLen u16 (1..4096)
//   header = deterministic CBOR map with integer keys 1..12, in this order.
//
// This file holds the constants, the non-secret value types (KDF parameters,
// key slot, header metadata) and the strict encoder/decoder. The decoder
// throws BackupCryptoException(corruptHeader | unsupportedKdf) only.

import 'dart:convert';
import 'dart:typed_data';

import 'backup_crypto_exception.dart';
import 'strict_cbor.dart';

/// "ZGLB".
const List<int> backupMagic = [0x5a, 0x47, 0x4c, 0x42];
const int backupFormatVersion = 1;
const int backupPrefixLength = 7;
const int maxHeaderLength = 4096;

const int defaultChunkSize = 1 << 20;
const int minChunkSize = 1 << 16;
const int maxChunkSize = 1 << 22;
const int maxChunks = 65536;
const int gcmTagLength = 16;
const int gcmNonceLength = 12;

/// Contents layouts this app can read (T-149 owns the meaning).
const int contentsVersionV1 = 1;
const int maxKnownContentsVersion = contentsVersionV1;

const int keyLength = 32;
const int saltLength = 16;
const int kbkIdLength = 16;
const int fileIdLength = 16;
const int noncePrefixLength = 8;
const int wrappedKeyLength = keyLength + gcmTagLength;
const int maxAppVersionBytes = 32;

const int kdfAlgArgon2id = 1;
const int wrapAlgAesGcm = 1;

/// v1 KDF parameters (ADR-011): 64 MiB, t = 3, p = 1.
const int v1MemoryKiB = 65536;
const int v1Iterations = 3;
const int v1Parallelism = 1;

/// Restore-side bounds (design note §5): anything else is refused before the
/// KDF runs.
const int minMemoryKiB = 19456;
const int maxMemoryKiB = 262144;
const int minIterations = 1;
const int maxIterations = 10;
const int minParallelism = 1;
const int maxParallelism = 4;

/// HKDF info labels and the wrap AAD label (ASCII).
final Uint8List keyIdInfo = ascii('ZGLB v1 key-id');
final Uint8List chunkKeyInfo = ascii('ZGLB v1 chunk');
final Uint8List snapshotKeyInfo = ascii('ZGLB v1 db-snapshot');
final Uint8List wrapAadLabel = ascii('ZGLB v1 wrap');

Uint8List ascii(String s) =>
    Uint8List.fromList(const AsciiEncoder().convert(s));

BackupCryptoException _corrupt() =>
    BackupCryptoException(BackupCryptoErrorCode.corruptHeader);

/// Argon2id parameters as stored in the header (`kdf`, key 1).
final class KdfParams {
  KdfParams({
    required List<int> salt,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  }) : salt = Uint8List.fromList(salt) {
    if (this.salt.length != saltLength) {
      throw ArgumentError.value(salt.length, 'salt.length');
    }
  }

  /// The v1 parameters with [salt].
  factory KdfParams.v1(List<int> salt) => KdfParams(
    salt: salt,
    memoryKiB: v1MemoryKiB,
    iterations: v1Iterations,
    parallelism: v1Parallelism,
  );

  final Uint8List salt;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// True when the parameters are inside the restore-side bounds.
  bool get withinBounds =>
      memoryKiB >= minMemoryKiB &&
      memoryKiB <= maxMemoryKiB &&
      iterations >= minIterations &&
      iterations <= maxIterations &&
      parallelism >= minParallelism &&
      parallelism <= maxParallelism;

  void _write(CborWriter w) {
    w
      ..mapHeader(5)
      ..uint(1)
      ..uint(kdfAlgArgon2id)
      ..uint(2)
      ..bytes(salt)
      ..uint(3)
      ..uint(memoryKiB)
      ..uint(4)
      ..uint(iterations)
      ..uint(5)
      ..uint(parallelism);
  }

  /// Canonical CBOR of the `kdf` map (part of the wrap AAD).
  Uint8List toCbor() {
    final w = CborWriter();
    _write(w);
    return w.takeBytes();
  }

  /// Strict decode. A wrong shape is corruptHeader; an unknown algorithm or
  /// out-of-bounds parameters are unsupportedKdf.
  static KdfParams _read(CborReader r) {
    if (r.readMapHeader() != 5) throw const CborFormatException();
    r.expectKey(1);
    final alg = r.readUint();
    r.expectKey(2);
    final salt = r.readBytes(saltLength);
    r.expectKey(3);
    final m = r.readUint();
    r.expectKey(4);
    final t = r.readUint();
    r.expectKey(5);
    final p = r.readUint();
    final params = KdfParams(
      salt: salt,
      memoryKiB: m,
      iterations: t,
      parallelism: p,
    );
    // Checked after the whole map parsed, so a shape error elsewhere wins.
    params._algorithm = alg;
    return params;
  }

  int _algorithm = kdfAlgArgon2id;

  bool get _supported => _algorithm == kdfAlgArgon2id && withinBounds;

  @override
  String toString() =>
      'KdfParams(argon2id, m: $memoryKiB KiB, t: $iterations, p: $parallelism)';
}

/// The non-secret key slot `{kdf, wrap, kbkId}` (design note §3). Reused byte
/// for byte in every file written with the same K_bk.
final class KeySlot {
  KeySlot({
    required this.kdf,
    required List<int> wrapNonce,
    required List<int> wrappedKey,
    required List<int> kbkId,
  }) : wrapNonce = Uint8List.fromList(wrapNonce),
       wrappedKey = Uint8List.fromList(wrappedKey),
       kbkId = Uint8List.fromList(kbkId) {
    if (this.wrapNonce.length != gcmNonceLength ||
        this.wrappedKey.length != wrappedKeyLength ||
        this.kbkId.length != kbkIdLength) {
      throw ArgumentError('KEY_SLOT_SHAPE');
    }
  }

  final KdfParams kdf;
  final Uint8List wrapNonce;

  /// `K_bk ‖ tag` under KEK_pass.
  final Uint8List wrappedKey;
  final Uint8List kbkId;

  /// AAD of the wrap: "ZGLB v1 wrap" ‖ CBOR(kdf) ‖ kbkId.
  Uint8List wrapAad() {
    final b = BytesBuilder(copy: false)
      ..add(wrapAadLabel)
      ..add(kdf.toCbor())
      ..add(kbkId);
    return b.takeBytes();
  }

  void _writeEntries(CborWriter w) {
    w.uint(1);
    kdf._write(w);
    w
      ..uint(2)
      ..mapHeader(3)
      ..uint(1)
      ..uint(wrapAlgAesGcm)
      ..uint(2)
      ..bytes(wrapNonce)
      ..uint(3)
      ..bytes(wrappedKey)
      ..uint(3)
      ..bytes(kbkId);
  }

  /// Canonical CBOR `{1: kdf, 2: wrap, 3: kbkId}`: the stored form
  /// (`secure_state` key `backup.key_slot.v1`).
  Uint8List toCbor() {
    final w = CborWriter()..mapHeader(3);
    _writeEntries(w);
    return w.takeBytes();
  }

  /// Reads keys 1..3 (the caller has read the map header).
  static KeySlot _readEntries(CborReader r) {
    r.expectKey(1);
    final kdf = KdfParams._read(r);
    r.expectKey(2);
    if (r.readMapHeader() != 3) throw const CborFormatException();
    r.expectKey(1);
    final wrapAlg = r.readUint();
    r.expectKey(2);
    final nonce = r.readBytes(gcmNonceLength);
    r.expectKey(3);
    final ct = r.readBytes(wrappedKeyLength);
    r.expectKey(3);
    final kbkId = r.readBytes(kbkIdLength);
    if (wrapAlg != wrapAlgAesGcm) throw const CborFormatException();
    return KeySlot(kdf: kdf, wrapNonce: nonce, wrappedKey: ct, kbkId: kbkId);
  }

  /// Strict decode of the stored form. Throws corruptHeader or
  /// unsupportedKdf.
  static KeySlot fromCbor(Uint8List bytes) {
    final KeySlot slot;
    try {
      final r = CborReader(bytes);
      if (r.readMapHeader() != 3) throw const CborFormatException();
      slot = _readEntries(r);
      if (!r.atEnd) throw const CborFormatException();
    } on CborFormatException {
      throw _corrupt();
    } on ArgumentError {
      throw _corrupt();
    }
    if (!slot.kdf._supported) {
      throw BackupCryptoException(BackupCryptoErrorCode.unsupportedKdf);
    }
    return slot;
  }

  /// Byte equality of the stored form (non-secret).
  bool sameAs(KeySlot other) {
    final a = toCbor();
    final b = other.toCbor();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'KeySlot($kdf)';
}

/// The writing platform (header key 11).
enum BackupPlatform { android, ios }

/// Caller-supplied header values (design note §2, keys 8..12). `createdAt`
/// comes from the cipher's clock.
final class HeaderMeta {
  HeaderMeta({
    required this.seq,
    required this.schemaVersion,
    required this.platform,
    required this.appVersion,
    this.contentsVersion = contentsVersionV1,
  }) {
    if (seq < 0 || schemaVersion < 0 || contentsVersion < 1) {
      throw ArgumentError('HEADER_META_RANGE');
    }
    if (!isValidAppVersion(appVersion)) {
      throw ArgumentError('HEADER_META_APP_VERSION');
    }
  }

  final int seq;
  final int schemaVersion;
  final int contentsVersion;
  final BackupPlatform platform;
  final String appVersion;

  /// 1..32 printable ASCII characters.
  static bool isValidAppVersion(String v) =>
      v.isNotEmpty &&
      v.length <= maxAppVersionBytes &&
      v.codeUnits.every((c) => c >= 0x20 && c <= 0x7e);
}

/// A decoded (or about to be written) header. Nothing here is secret, but
/// [fileId] is still never logged (design note §8).
final class BackupHeader {
  BackupHeader({
    required this.slot,
    required List<int> fileId,
    required List<int> noncePrefix,
    required this.chunkSize,
    required this.createdAtMs,
    required this.meta,
  }) : fileId = Uint8List.fromList(fileId),
       noncePrefix = Uint8List.fromList(noncePrefix) {
    if (this.fileId.length != fileIdLength ||
        this.noncePrefix.length != noncePrefixLength ||
        !isAllowedChunkSize(chunkSize) ||
        createdAtMs < 0) {
      throw ArgumentError('HEADER_SHAPE');
    }
  }

  final KeySlot slot;
  final Uint8List fileId;
  final Uint8List noncePrefix;
  final int chunkSize;
  final int createdAtMs;
  final HeaderMeta meta;

  static bool isAllowedChunkSize(int size) =>
      size >= minChunkSize && size <= maxChunkSize && (size & (size - 1)) == 0;

  /// `prefix ‖ header` exactly as written.
  Uint8List encodeBlock() {
    final w = CborWriter()..mapHeader(12);
    slot._writeEntries(w);
    w
      ..uint(4)
      ..bytes(fileId)
      ..uint(5)
      ..bytes(noncePrefix)
      ..uint(6)
      ..uint(chunkSize)
      ..uint(7)
      ..uint(createdAtMs)
      ..uint(8)
      ..uint(meta.seq)
      ..uint(9)
      ..uint(meta.schemaVersion)
      ..uint(10)
      ..uint(meta.contentsVersion)
      ..uint(11)
      ..text(meta.platform.name)
      ..uint(12)
      ..text(meta.appVersion);
    final header = w.takeBytes();
    if (header.isEmpty || header.length > maxHeaderLength) {
      throw StateError('HEADER_TOO_LONG');
    }
    final out = Uint8List(backupPrefixLength + header.length)
      ..setRange(0, 4, backupMagic)
      ..[4] = backupFormatVersion
      ..[5] = header.length >> 8
      ..[6] = header.length & 0xff
      ..setRange(
        backupPrefixLength,
        backupPrefixLength + header.length,
        header,
      );
    return out;
  }

  /// Strict decode of the CBOR header (without the prefix). Shape and
  /// canonical-form violations are corruptHeader; KDF algorithm or bounds are
  /// unsupportedKdf (checked after the whole header parsed).
  static BackupHeader decode(Uint8List header) {
    final BackupHeader h;
    try {
      final r = CborReader(header);
      if (r.readMapHeader() != 12) throw const CborFormatException();
      final slot = KeySlot._readEntries(r);
      r.expectKey(4);
      final fileId = r.readBytes(fileIdLength);
      r.expectKey(5);
      final noncePrefix = r.readBytes(noncePrefixLength);
      r.expectKey(6);
      final chunkSize = r.readUint();
      r.expectKey(7);
      final createdAt = r.readUint();
      r.expectKey(8);
      final seq = r.readUint();
      r.expectKey(9);
      final schema = r.readUint();
      r.expectKey(10);
      final contents = r.readUint();
      r.expectKey(11);
      final platformName = r.readText(maxBytes: 7);
      r.expectKey(12);
      final appVersion = r.readText(maxBytes: maxAppVersionBytes);
      if (!r.atEnd) throw const CborFormatException();
      final platform = BackupPlatform.values
          .where((p) => p.name == platformName)
          .firstOrNull;
      if (platform == null ||
          !isAllowedChunkSize(chunkSize) ||
          contents < 1 ||
          !HeaderMeta.isValidAppVersion(appVersion)) {
        throw const CborFormatException();
      }
      h = BackupHeader(
        slot: slot,
        fileId: fileId,
        noncePrefix: noncePrefix,
        chunkSize: chunkSize,
        createdAtMs: createdAt,
        meta: HeaderMeta(
          seq: seq,
          schemaVersion: schema,
          contentsVersion: contents,
          platform: platform,
          appVersion: appVersion,
        ),
      );
    } on CborFormatException {
      throw _corrupt();
    } on ArgumentError {
      throw _corrupt();
    }
    if (!h.slot.kdf._supported) {
      throw BackupCryptoException(BackupCryptoErrorCode.unsupportedKdf);
    }
    return h;
  }

  @override
  String toString() =>
      'BackupHeader(v$backupFormatVersion, chunkSize: $chunkSize, '
      'schema: ${meta.schemaVersion}, contents: ${meta.contentsVersion})';
}

/// The parsed prefix: (formatVersion, headerLen). Throws notABackup,
/// newerFormat or corruptHeader (design note §7 step 1). [prefix] holds the
/// bytes actually read (possibly fewer than 7 at end of file).
int parsePrefix(Uint8List prefix) {
  for (var i = 0; i < backupMagic.length; i++) {
    if (i >= prefix.length || prefix[i] != backupMagic[i]) {
      throw BackupCryptoException(BackupCryptoErrorCode.notABackup);
    }
  }
  if (prefix.length < 5) throw _corrupt();
  final version = prefix[4];
  if (version > backupFormatVersion) {
    throw BackupCryptoException(BackupCryptoErrorCode.newerFormat);
  }
  if (version == 0 || prefix.length < backupPrefixLength) throw _corrupt();
  final headerLen = (prefix[5] << 8) | prefix[6];
  if (headerLen == 0 || headerLen > maxHeaderLength) throw _corrupt();
  return headerLen;
}
