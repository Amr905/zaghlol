// T-148: streaming encrypt/decrypt of format v1 (design note §2, §6, §7).
//
//   nonce_i = noncePrefix ‖ u32(i)                    (derived, never stored)
//   AAD_i   = headerBlock ‖ u32(i) ‖ u8(isLast)
//   chunk_i = AES-256-GCM(K_chunk, nonce_i, plaintext_i, AAD_i) = ct ‖ tag
//
// Every chunk but the last holds exactly chunkSize plaintext bytes; the last
// holds 1..chunkSize (0 only for an empty payload, one chunk). At most 65 536
// chunks. Peak memory is about two chunks plus the input event. Pure Dart.

import 'dart:async';
import 'dart:typed_data';

import 'backup_crypto_exception.dart';
import 'backup_format.dart';
import 'backup_keys.dart';
import 'backup_primitives.dart';
import 'byte_reader.dart';
import 'secret_bytes.dart';

/// The per-chunk nonce.
Uint8List chunkNonce(Uint8List noncePrefix, int index) {
  final n = Uint8List(gcmNonceLength)
    ..setRange(0, noncePrefixLength, noncePrefix);
  n[8] = (index >> 24) & 0xff;
  n[9] = (index >> 16) & 0xff;
  n[10] = (index >> 8) & 0xff;
  n[11] = index & 0xff;
  return n;
}

/// A reusable AAD buffer: headerBlock ‖ u32(i) ‖ u8(isLast).
final class _Aad {
  _Aad(Uint8List headerBlock)
    : buffer = Uint8List(headerBlock.length + 5)
        ..setRange(0, headerBlock.length, headerBlock);

  final Uint8List buffer;

  Uint8List at(int index, {required bool isLast}) {
    final o = buffer.length - 5;
    buffer[o] = (index >> 24) & 0xff;
    buffer[o + 1] = (index >> 16) & 0xff;
    buffer[o + 2] = (index >> 8) & 0xff;
    buffer[o + 3] = index & 0xff;
    buffer[o + 4] = isLast ? 1 : 0;
    return buffer;
  }
}

BackupCryptoException _asCrypto(Object e, BackupCryptoErrorCode fallback) =>
    e is BackupCryptoException ? e : BackupCryptoException(fallback);

/// Emits headerBlock then every sealed chunk of [plaintext]. Any failure
/// ends the stream with a BackupCryptoException (fail closed: the caller
/// deletes partial output; there is no unencrypted fallback).
Stream<List<int>> encryptStream({
  required BackupPrimitives primitives,
  required BackupKeys keys,
  required BackupHeader header,
  required Stream<List<int>> plaintext,
  // Tests only: a lower limit than the format's 65 536.
  int chunkLimit = maxChunks,
}) async* {
  final headerBlock = header.encodeBlock();
  final chunkSize = header.chunkSize;
  final aad = _Aad(headerBlock);
  SecretBytes? kChunk;
  final buf = Uint8List(chunkSize);
  try {
    kChunk = await keys.chunkKey(header.fileId);
    yield headerBlock;
    var fill = 0;
    var index = 0;
    Future<Uint8List> seal(int length, {required bool isLast}) {
      if (index >= chunkLimit) {
        throw BackupCryptoException(BackupCryptoErrorCode.io);
      }
      return primitives.seal(
        key: kChunk!,
        nonce: chunkNonce(header.noncePrefix, index),
        plaintext: Uint8List.sublistView(buf, 0, length),
        aad: aad.at(index, isLast: isLast),
      );
    }

    try {
      await for (final data in plaintext) {
        var off = 0;
        while (off < data.length) {
          if (fill == chunkSize) {
            // More input follows, so the full buffer is not the last chunk.
            yield await seal(fill, isLast: false);
            index++;
            fill = 0;
          }
          final room = chunkSize - fill;
          final left = data.length - off;
          final take = room < left ? room : left;
          buf.setRange(fill, fill + take, data, off);
          fill += take;
          off += take;
        }
      }
    } on BackupCryptoException {
      rethrow;
    } on Object {
      // The plaintext source failed.
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    }
    yield await seal(fill, isLast: true);
  } on Object catch (e) {
    throw _asCrypto(e, BackupCryptoErrorCode.io);
  } finally {
    kChunk?.zeroize();
    buf.fillRange(0, buf.length, 0);
  }
}

/// Reads and decodes prefix and header (design note §7 steps 1–2). Returns
/// the exact headerBlock bytes and the decoded header. Throws notABackup,
/// newerFormat, corruptHeader, unsupportedKdf or io.
Future<(Uint8List, BackupHeader)> readHeader(ByteReader reader) async {
  final prefix = await reader.read(backupPrefixLength);
  final headerLen = parsePrefix(prefix);
  final header = await reader.read(headerLen);
  if (header.length != headerLen) {
    throw BackupCryptoException(BackupCryptoErrorCode.corruptHeader);
  }
  final decoded = BackupHeader.decode(header);
  final block = Uint8List(backupPrefixLength + headerLen)
    ..setRange(0, backupPrefixLength, prefix)
    ..setRange(backupPrefixLength, backupPrefixLength + headerLen, header);
  return (block, decoded);
}

/// Authenticates and yields every chunk's plaintext (design note §7 step 5).
/// A chunk is last exactly when the stream ends right after it. Any tag
/// failure, a chunk shorter than a tag, an empty non-first last chunk, a
/// missing chunk or more than 65 536 chunks is corruptData. The yielded
/// plaintext is untrusted until the generator completes normally.
Stream<Uint8List> decryptChunks({
  required BackupPrimitives primitives,
  required SecretBytes chunkKey,
  required Uint8List headerBlock,
  required BackupHeader header,
  required ByteReader reader,
  // Tests only: a lower limit than the format's 65 536.
  int chunkLimit = maxChunks,
}) async* {
  final aad = _Aad(headerBlock);
  final sealedSize = header.chunkSize + gcmTagLength;
  var index = 0;
  while (true) {
    if (index >= chunkLimit) {
      throw BackupCryptoException(BackupCryptoErrorCode.corruptData);
    }
    final sealed = await reader.read(sealedSize);
    final bool isLast;
    if (sealed.length < sealedSize) {
      // A short read is always the last chunk. Only chunk 0 may be empty
      // (exactly a tag): an empty payload.
      isLast = true;
      if (sealed.length < gcmTagLength ||
          (sealed.length == gcmTagLength && index != 0)) {
        throw BackupCryptoException(BackupCryptoErrorCode.corruptData);
      }
    } else {
      isLast = await reader.atEnd;
    }
    final Uint8List clear;
    try {
      clear = await primitives.open(
        key: chunkKey,
        nonce: chunkNonce(header.noncePrefix, index),
        sealed: sealed,
        aad: aad.at(index, isLast: isLast),
      );
    } on AeadAuthenticationFailure {
      throw BackupCryptoException(BackupCryptoErrorCode.corruptData);
    }
    yield clear;
    if (isLast) return;
    index++;
  }
}
