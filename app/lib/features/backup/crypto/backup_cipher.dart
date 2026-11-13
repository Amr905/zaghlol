// T-148: the backup crypto façade (design note §3, §6, §7, §8). Stateless: it
// never caches keys. Pure Dart; the secret store, the key slot store and the
// normalizer are injected.
//
// Key storage (design note §3): K_bk lives in the SecretStore slot
// `backupKey` (written under the bootstrap lease), the non-secret key slot in
// the encrypted DB (BackupKeySlotStore; `secure_state` key
// `backup.key_slot.v1`). Both are written under the same lease, secret first,
// so two concurrent key changes can't interleave; a crash between the two
// leaves a detectable mismatch (keyMismatch → passphrase prompt), never a
// file written with a wrong pairing.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/crypto/secret_store.dart';
import 'backup_crypto_exception.dart';
import 'backup_format.dart';
import 'backup_keys.dart';
import 'backup_primitives.dart';
import 'backup_stream.dart';
import 'byte_reader.dart';
import 'passphrase.dart';
import 'passphrase_kdf.dart';
import 'secret_bytes.dart';

/// Stores the non-secret key slot (canonical CBOR, KeySlot.toCbor) in the
/// encrypted DB. The DB adapter lands with the `secure_state` table (T-019);
/// T-149 excludes the row from the snapshot.
abstract interface class BackupKeySlotStore {
  /// The stored slot, or null on **positive** evidence that none is stored.
  /// Throws on any error (never null on doubt).
  Future<Uint8List?> read();

  /// Replaces the stored slot in one transaction. Throws on failure.
  Future<void> write(Uint8List slotCbor);
}

/// Random bytes for keys, salts, nonces and file ids.
abstract interface class BackupRandom {
  Uint8List bytes(int length);
}

/// `Random.secure()`.
final class SecureBackupRandom implements BackupRandom {
  SecureBackupRandom([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  @override
  Uint8List bytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}

/// How long to wait for the bootstrap lease.
const Duration backupLeaseTimeout = Duration(seconds: 10);

/// The authenticated outcome of a decrypt (design note §7 step 7).
final class BackupOpenResult {
  BackupOpenResult._(this.header, this.keys, this.chunks);

  /// The header; authenticated by every chunk's AAD.
  final BackupHeader header;

  /// K_bk and the slot of the restored file, for T-149 to store after the
  /// swap. The receiver owns them and must zeroize.
  final BackupKeys keys;

  /// Number of chunks read.
  final int chunks;

  int get createdAtMs => header.createdAtMs;
  int get seq => header.meta.seq;
  int get schemaVersion => header.meta.schemaVersion;
  BackupPlatform get platform => header.meta.platform;
  String get appVersion => header.meta.appVersion;
  KeySlot get slot => header.slot;

  @override
  String toString() => 'BackupOpenResult(chunks: $chunks)';
}

/// A file whose passphrase was accepted (design note §7 steps 1–4 passed).
///
/// Contract with T-149 (step 6): the [plaintext] is **untrusted until [done]
/// completes**. Write it only to a temp location, commit nothing before
/// [done], and delete the temp output on any error. [plaintext] may be
/// listened to once; [done] completes after the last chunk authenticated,
/// or with the same BackupCryptoException the stream ended with (also when
/// the consumer cancels: io).
final class DecryptSession {
  DecryptSession._(
    this.header,
    this._keys,
    this._chunkKey,
    this._headerBlock,
    this._reader,
    this._primitives,
  ) {
    // Nobody may have to listen to `done` for its error to stay handled.
    _done.future.ignore();
  }

  /// The decoded header. Only the KDF parameters and kbkId are authenticated
  /// at this point (by the wrap); the rest only once [done] completes.
  final BackupHeader header;

  final BackupKeys _keys;
  final SecretBytes _chunkKey;
  final Uint8List _headerBlock;
  final ByteReader _reader;
  final BackupPrimitives _primitives;
  final Completer<BackupOpenResult> _done = Completer<BackupOpenResult>();
  bool _listened = false;

  Future<BackupOpenResult> get done => _done.future;

  /// K_snap for this file (T-149). The caller zeroes it.
  Future<SecretBytes> snapshotKey() => _keys.snapshotKey(header.fileId);

  /// The decrypted payload, chunk by chunk.
  Stream<Uint8List> get plaintext {
    if (_listened) throw StateError('BACKUP_SESSION_ALREADY_READ');
    _listened = true;
    return _run();
  }

  Stream<Uint8List> _run() async* {
    var chunks = 0;
    var completed = false;
    try {
      await for (final clear in decryptChunks(
        primitives: _primitives,
        chunkKey: _chunkKey,
        headerBlock: _headerBlock,
        header: header,
        reader: _reader,
      )) {
        chunks++;
        yield clear;
      }
      completed = true;
      _done.complete(BackupOpenResult._(header, _keys, chunks));
    } on Object catch (e) {
      final err = e is BackupCryptoException
          ? e
          : BackupCryptoException(BackupCryptoErrorCode.io);
      _fail(err);
      throw err;
    } finally {
      _chunkKey.zeroize();
      await _reader.cancel();
      if (!completed) {
        // Cancelled by the consumer before the end.
        _fail(BackupCryptoException(BackupCryptoErrorCode.io));
      }
    }
  }

  void _fail(BackupCryptoException e) {
    if (_done.isCompleted) return;
    _keys.zeroize();
    _done.completeError(e);
  }

  /// Abandons the session without reading (zeroes the keys, closes the
  /// input). Safe to call at any time; a completed [done] keeps its keys.
  Future<void> dispose() async {
    if (!_listened) {
      _listened = true;
      _chunkKey.zeroize();
      await _reader.cancel();
      _fail(BackupCryptoException(BackupCryptoErrorCode.io));
    }
  }

  @override
  String toString() => 'DecryptSession($header)';
}

final class BackupCipher {
  BackupCipher({
    required SecretStore secretStore,
    required BackupKeySlotStore slotStore,
    required TextNormalizer normalizer,
    BackupRandom? random,
    DateTime Function()? clock,
    PassphraseKdf? kdf,
    BackupPrimitives? primitives,
    this._leaseTimeout = backupLeaseTimeout,
  }) : _store = secretStore,
       _slots = slotStore,
       _encoder = PassphraseEncoder(normalizer),
       _random = random ?? SecureBackupRandom(),
       _clock = clock ?? DateTime.now,
       _kdf = kdf ?? const Argon2idKdf(),
       _schedule = BackupKeySchedule(primitives ?? BackupPrimitives());

  final SecretStore _store;
  final BackupKeySlotStore _slots;
  final PassphraseEncoder _encoder;
  final BackupRandom _random;
  final DateTime Function() _clock;
  final PassphraseKdf _kdf;
  final BackupKeySchedule _schedule;
  final Duration _leaseTimeout;

  BackupPrimitives get _primitives => _schedule.primitives;

  // ---------------------------------------------------------------- keys

  /// KEK_pass for [passphrase] under [kdf]. Zeroes P.
  Future<SecretBytes> _kek(Uint8List p, KdfParams kdf) async {
    try {
      return await _kdf.derive(p, kdf);
    } finally {
      wipe(p);
    }
  }

  /// A fresh K_bk; an all-equal output (a broken generator) is refused.
  SecretBytes _newKbk() {
    final bytes = _random.bytes(keyLength);
    if (bytes.length != keyLength || bytes.every((b) => b == bytes[0])) {
      wipe(bytes);
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    }
    return SecretBytes.adopt(bytes);
  }

  /// Builds a new K_bk and its slot for [passphrase] without storing them
  /// (design note §3). Runs the KDF.
  Future<BackupKeys> _mintKeys(String passphrase) async {
    final p = await _encoder.encodeNew(passphrase);
    final kdf = KdfParams.v1(_random.bytes(saltLength));
    final kek = await _kek(p, kdf);
    try {
      return await _schedule.wrap(
        kbk: _newKbk(),
        kek: kek,
        kdf: kdf,
        wrapNonce: _random.bytes(gcmNonceLength),
      );
    } finally {
      kek.zeroize();
    }
  }

  /// First setup and passphrase change (design note §3: a change **rotates**
  /// K_bk). Mints a new K_bk and slot, then under the lease: deletes the old
  /// `backupKey`, stores the new one, reads it back, and only then replaces
  /// the slot. Files written before stay readable with the old passphrase
  /// only. What happens to them is PROVISIONAL — PO to confirm (§11 q1).
  ///
  /// Throws passphraseTooShort, kdfOutOfMemory, keyUnavailable or io. On a
  /// failure after the old secret was deleted, the slot still names the old
  /// key: the next backup reports keyMismatch and asks for the old passphrase
  /// (recoverWithPassphrase), so nothing is written with a wrong pairing.
  Future<BackupKeys> createKey(String passphrase) async {
    final keys = await _mintKeys(passphrase);
    try {
      await _withLease((lease) async {
        await _ensureLease(lease);
        await _guardStore(() => _store.delete(lease, SecretSlot.backupKey));
        await _storeSecret(lease, keys);
        await _ensureLease(lease);
        await _guardSlots(() => _slots.write(keys.slot.toCbor()));
      });
      return keys;
    } on Object {
      keys.zeroize();
      rethrow;
    }
  }

  /// Same as [createKey] (design note §3: `changePassphrase(new) =
  /// createKey(new)`).
  Future<BackupKeys> changePassphrase(String newPassphrase) =>
      createKey(newPassphrase);

  /// The keys for an automatic backup (no passphrase, no KDF). Null when
  /// backup was never set up (no slot, positively). Throws keyMismatch when
  /// the stored key is missing, unusable or doesn't match the slot (ask for
  /// the passphrase: [recoverWithPassphrase]), keyUnavailable when the store
  /// can't answer (retry later, never re-key).
  Future<BackupKeys?> loadKeys() async {
    final slot = await _readSlot();
    if (slot == null) return null;
    final read = await _store.read(SecretSlot.backupKey);
    switch (read.status) {
      case SecretStatus.found:
        final value = read.value!;
        final kbk = SecretBytes.copyOf(value);
        wipe(value);
        return _schedule.adopt(kbk: kbk, slot: slot);
      case SecretStatus.notFound:
      case SecretStatus.unusable:
        throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
      case SecretStatus.unavailable:
        throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
  }

  /// Recovery without a new key (design note §3): unwraps the **local** slot
  /// with [passphrase] and stores K_bk again. Old backups stay readable.
  /// Throws wrongPassphrase, keyMismatch (no usable slot), keyUnavailable
  /// (the store can't answer: nothing is rewritten) or io.
  Future<BackupKeys> recoverWithPassphrase(String passphrase) async {
    final slot = await _readSlot();
    if (slot == null) {
      throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
    }
    final keys = await _unlockSlot(slot, passphrase);
    try {
      await _withLease((lease) async {
        // Ownership re-check: the slot must still be the one we unwrapped
        // (another actor may have changed the passphrase meanwhile).
        final current = await _readSlot();
        if (current == null || !current.sameAs(slot)) {
          throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
        }
        final read = await _store.read(SecretSlot.backupKey);
        switch (read.status) {
          case SecretStatus.found:
            final value = read.value!;
            final existing = SecretBytes.copyOf(value);
            wipe(value);
            final same = keys.sameKeyAs(existing);
            existing.zeroize();
            if (same) return;
            // A key that doesn't match the slot: the leftover of a crash
            // between secret and slot write. No file was ever written with
            // it (loadKeys refuses the pairing), so replacing it loses
            // nothing.
            await _ensureLease(lease);
            await _guardStore(() => _store.delete(lease, SecretSlot.backupKey));
          case SecretStatus.unusable:
            // Positive evidence that it can never be read again.
            await _ensureLease(lease);
            await _guardStore(() => _store.delete(lease, SecretSlot.backupKey));
          case SecretStatus.notFound:
            break;
          case SecretStatus.unavailable:
            throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
        }
        await _storeSecret(lease, keys);
      });
      return keys;
    } on Object {
      keys.zeroize();
      rethrow;
    }
  }

  /// T-149 (restore step 8): after the restored database (which already
  /// carries [keys]' slot) is swapped in, store the restored K_bk so
  /// automatic backups continue without the passphrase. Under the lease: the
  /// stored slot must be [keys]' slot (ownership check); an equal stored key
  /// is kept; any other is replaced (it pairs with no slot any more).
  /// Throws keyMismatch (the slot is not the restored one) or keyUnavailable.
  /// A crash before this completes leaves slot ≠ secret: loadKeys reports
  /// keyMismatch and recoverWithPassphrase repairs it.
  Future<void> storeRestoredKey(BackupKeys keys) => _withLease((lease) async {
    final current = await _readSlot();
    if (current == null || !current.sameAs(keys.slot)) {
      throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
    }
    final read = await _guardStore(() => _store.read(SecretSlot.backupKey));
    switch (read.status) {
      case SecretStatus.found:
        final value = read.value!;
        final existing = SecretBytes.copyOf(value);
        wipe(value);
        final same = keys.sameKeyAs(existing);
        existing.zeroize();
        if (same) return;
        await _ensureLease(lease);
        await _guardStore(() => _store.delete(lease, SecretSlot.backupKey));
      case SecretStatus.unusable:
        await _ensureLease(lease);
        await _guardStore(() => _store.delete(lease, SecretSlot.backupKey));
      case SecretStatus.notFound:
        break;
      case SecretStatus.unavailable:
        throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
    await _storeSecret(lease, keys);
  });

  Future<BackupKeys> _unlockSlot(KeySlot slot, String passphrase) async {
    if (!slot.kdf.withinBounds) {
      throw BackupCryptoException(BackupCryptoErrorCode.unsupportedKdf);
    }
    final p = await _encoder.encode(passphrase);
    final kek = await _kek(p, slot.kdf);
    try {
      return await _schedule.unwrap(slot: slot, kek: kek);
    } finally {
      kek.zeroize();
    }
  }

  Future<KeySlot?> _readSlot() async {
    final Uint8List? raw;
    try {
      raw = await _slots.read();
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
    if (raw == null) return null;
    try {
      return KeySlot.fromCbor(raw);
    } on BackupCryptoException {
      // A stored slot that can't be decoded can't unwrap anything; the user
      // sets the passphrase up again (createKey).
      throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
    }
  }

  /// createIfAbsent + read-back; the stored value must equal K_bk.
  Future<void> _storeSecret(SecretStoreLease lease, BackupKeys keys) async {
    await _ensureLease(lease);
    final candidate = keys.exportKey();
    final Uint8List stored;
    try {
      stored = await _guardStore(
        () => _store.createIfAbsent(
          lease,
          SecretSlot.backupKey,
          Uint8List.fromList(candidate.bytes),
        ),
      );
    } finally {
      candidate.zeroize();
    }
    final storedKey = SecretBytes.copyOf(stored);
    wipe(stored);
    final same = keys.sameKeyAs(storedKey);
    storedKey.zeroize();
    if (!same) {
      // Another writer's key won the race: never pair it with our slot.
      throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
    final back = await _store.read(SecretSlot.backupKey);
    final value = back.value;
    var ok = false;
    if (back.status == SecretStatus.found && value != null) {
      final readBack = SecretBytes.copyOf(value);
      ok = keys.sameKeyAs(readBack);
      readBack.zeroize();
    }
    if (value != null) wipe(value);
    if (!ok) throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
  }

  Future<void> _withLease(
    Future<void> Function(SecretStoreLease lease) body,
  ) async {
    final lease = await _guardStore(
      () => _store.acquireBootstrapLease(_leaseTimeout),
    );
    try {
      await body(lease);
    } finally {
      await _store.releaseBootstrapLease(lease);
    }
  }

  Future<void> _ensureLease(SecretStoreLease lease) async {
    if (!await _store.renewBootstrapLease(lease)) {
      throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
  }

  Future<T> _guardStore<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BackupCryptoException {
      rethrow;
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
  }

  Future<void> _guardSlots(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.keyUnavailable);
    }
  }

  // -------------------------------------------------------------- format

  /// A fresh random file id (T-149: chosen before [encrypt] so the snapshot
  /// key `K_snap = HKDF(K_bk, fileId)` exists before the header is written).
  Uint8List newFileId() => _random.bytes(fileIdLength);

  /// Encrypts [plaintext] into a v1 file (design note §6). [fileId]: from
  /// [newFileId] when the caller needs K_snap first (T-149); else fresh. [meta.seq] is the
  /// stored counter + 1 (T-150 persists it after the upload). Errors end the
  /// stream with a BackupCryptoException; the caller deletes partial output.
  Stream<List<int>> encrypt(
    BackupKeys keys,
    HeaderMeta meta,
    Stream<List<int>> plaintext, {
    int chunkSize = defaultChunkSize,
    Uint8List? fileId,
  }) {
    final BackupHeader header;
    try {
      if (fileId != null && fileId.length != fileIdLength) {
        throw ArgumentError('FILE_ID_LENGTH');
      }
      header = BackupHeader(
        slot: keys.slot,
        fileId: fileId ?? newFileId(),
        noncePrefix: _random.bytes(noncePrefixLength),
        chunkSize: chunkSize,
        createdAtMs: _clock().toUtc().millisecondsSinceEpoch,
        meta: meta,
      );
    } on Object {
      return Stream.error(BackupCryptoException(BackupCryptoErrorCode.io));
    }
    return encryptStream(
      primitives: _primitives,
      keys: keys,
      header: header,
      plaintext: plaintext,
    );
  }

  /// Opens [file] with [passphrase] (design note §7 steps 1–4): prefix, strict
  /// header, cheap refusals, then normalize, Argon2id, unwrap and the kbkId
  /// check. No chunk is read before the passphrase is accepted.
  Future<DecryptSession> open(
    Stream<List<int>> file,
    String passphrase, {
    required int maxSchemaVersion,
  }) async {
    final reader = ByteReader(file);
    try {
      final (block, header) = await readHeader(reader);
      _cheapRefusals(header, maxSchemaVersion);
      final keys = await _unlockSlot(header.slot, passphrase);
      final SecretBytes chunkKey;
      try {
        chunkKey = await keys.chunkKey(header.fileId);
      } on Object {
        keys.zeroize();
        rethrow;
      }
      return DecryptSession._(
        header,
        keys,
        chunkKey,
        block,
        reader,
        _primitives,
      );
    } on Object catch (e) {
      await reader.cancel();
      if (e is BackupCryptoException) rethrow;
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    }
  }

  /// Verify-after-write (design note §6): decrypts every chunk with [keys]
  /// and discards the plaintext; no KDF. The file must carry [keys]' slot.
  /// Throws keyMismatch, corruptHeader, corruptData, … ; returns the number
  /// of chunks.
  Future<int> verifyFile(Stream<List<int>> file, BackupKeys keys) async {
    final reader = ByteReader(file);
    SecretBytes? chunkKey;
    try {
      final (block, header) = await readHeader(reader);
      if (!header.slot.sameAs(keys.slot)) {
        throw BackupCryptoException(BackupCryptoErrorCode.keyMismatch);
      }
      chunkKey = await keys.chunkKey(header.fileId);
      var chunks = 0;
      await for (final clear in decryptChunks(
        primitives: _primitives,
        chunkKey: chunkKey,
        headerBlock: block,
        header: header,
        reader: reader,
      )) {
        wipe(clear);
        chunks++;
      }
      return chunks;
    } on Object catch (e) {
      if (e is BackupCryptoException) rethrow;
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    } finally {
      chunkKey?.zeroize();
      await reader.cancel();
    }
  }

  /// Design note §7 step 3: refusals that need no key (the header is not yet
  /// authenticated, so these only refuse, never accept).
  static void _cheapRefusals(BackupHeader header, int maxSchemaVersion) {
    if (header.meta.schemaVersion > maxSchemaVersion) {
      throw BackupCryptoException(BackupCryptoErrorCode.newerSchema);
    }
    if (header.meta.contentsVersion > maxKnownContentsVersion) {
      throw BackupCryptoException(BackupCryptoErrorCode.newerFormat);
    }
  }
}
