// T-015: secure key bootstrap for the database key K_db (security-model §3,
// FR-SEC-04/05, D-50). Design: docs/04-tasks/tasks/T-015.md "Design note".
//
// Rules this file keeps:
// - A new key is written only when no database file exists (DbFileSet). An
//   existing database with a missing or unusable key is KeyInvalidated: no
//   key is written and no file is touched.
// - Only positive evidence (SecretStatus.notFound / unusable) leads to
//   KeyInvalidated. Everything unknown is KeyUnavailable and never wipes.
// - Key bytes live only in DbKeyMaterial, whose toString is redacted. No
//   outcome prints key material. Nothing here logs (diag codes are emitted by
//   T-021's logger once it exists).
// - KeyBootstrap is stateless: it never caches an outcome or a key.

import 'dart:io' show FileSystemException;
import 'dart:math';
import 'dart:typed_data';

import '../crypto/secret_store.dart';
import 'db_file_set.dart';

/// Length of K_db in bytes (256-bit raw SQLCipher key).
const int dbKeyLength = 32;

/// How long [KeyBootstrap] waits for the process-wide bootstrap lease.
const Duration bootstrapLeaseTimeout = Duration(seconds: 10);

/// The database key in memory. Owns its bytes; the holder calls [zeroize]
/// right after the first successful open (design note §5).
///
/// No `==` / `hashCode` on the bytes, and [toString] is redacted. Use
/// [sameKeyAs] (constant time) to compare.
final class DbKeyMaterial {
  DbKeyMaterial._(this._bytes);

  /// Copies [bytes] (which must be [dbKeyLength] long) into a new key.
  factory DbKeyMaterial.copyOf(Uint8List bytes) {
    if (bytes.length != dbKeyLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'DB_KEY_LENGTH_INVALID',
      );
    }
    return DbKeyMaterial._(Uint8List.fromList(bytes));
  }

  final Uint8List _bytes;
  bool _zeroized = false;

  bool get isZeroized => _zeroized;

  /// Lowercase hex for `PRAGMA key = "x'…'"`. Call it only inside drift's
  /// `setup` closure and pass the result straight to the key statement (see
  /// encrypted_open.dart). Dart strings can't be wiped, so keep the result's
  /// lifetime to that one statement.
  String toRawKeyHex() {
    if (_zeroized) throw StateError('DB_KEY_ZEROIZED');
    final buf = StringBuffer();
    for (final b in _bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Constant-time comparison of the key bytes.
  bool sameKeyAs(DbKeyMaterial other) {
    if (_zeroized || other._zeroized) return false;
    var diff = _bytes.length ^ other._bytes.length;
    for (var i = 0; i < _bytes.length && i < other._bytes.length; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  /// Fills the bytes with zeros. Idempotent.
  void zeroize() {
    _bytes.fillRange(0, _bytes.length, 0);
    _zeroized = true;
  }

  @override
  String toString() => 'DbKeyMaterial(<redacted>)';
}

/// Makes candidate keys. The app uses [SecureKeyGenerator]; tests inject a
/// fixed synthetic generator.
abstract interface class KeyGenerator {
  /// Returns [dbKeyLength] fresh bytes, or null when no usable generator
  /// exists (no OS CSPRNG, or a broken one).
  Uint8List? next();
}

/// `Random.secure()` (the OS CSPRNG). Rejects an all-equal-bytes result as a
/// broken generator.
final class SecureKeyGenerator implements KeyGenerator {
  SecureKeyGenerator({Random Function()? random})
    : _random = random ?? Random.secure;

  final Random Function() _random;

  @override
  Uint8List? next() {
    final Random rng;
    try {
      rng = _random();
    } on UnsupportedError {
      return null; // no secure source on this platform
    }
    final out = Uint8List(dbKeyLength);
    for (var i = 0; i < out.length; i++) {
      out[i] = rng.nextInt(256);
    }
    if (isDegenerateKey(out)) {
      out.fillRange(0, out.length, 0);
      return null;
    }
    return out;
  }
}

/// Overwrites [bytes] with zeros where possible. Buffers decoded by the
/// platform channel codec can be unmodifiable views; those are skipped (the
/// codec buffer is freed but not wiped, an accepted limit, design note §5).
void wipeBytes(Uint8List bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Unmodifiable view: nothing to do.
  }
}

/// True for a key no healthy CSPRNG would produce in practice: wrong length or
/// all bytes equal.
bool isDegenerateKey(Uint8List bytes) {
  if (bytes.length != dbKeyLength) return true;
  final first = bytes.first;
  for (final b in bytes) {
    if (b != first) return false;
  }
  return true;
}

/// A held bootstrap lease. [KeyCreated] and [KeyInvalidated] return holding
/// one: the database owner (T-016) creates or wipes the database under it and
/// then calls [release]. Idempotent.
final class BootstrapLease {
  BootstrapLease._(this._store, this._lease);

  final SecretStore _store;
  final SecretStoreLease _lease;
  bool _released = false;

  bool get isReleased => _released;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _store.releaseBootstrapLease(_lease);
  }

  @override
  String toString() => 'BootstrapLease(${_released ? 'released' : 'held'})';
}

/// Why a new key was created.
enum KeyCreatedReason {
  /// No key and no database: the very first launch.
  firstRun,

  /// A key (usable or not) but no database, e.g. an iOS reinstall (the
  /// Keychain outlives the app, T-165): the old key is replaced.
  rotatedNoDb,

  /// After the database owner wiped an orphaned database
  /// ([KeyBootstrap.recreateAfterWipe]).
  afterWipe,
}

/// Why the existing database can't be opened.
enum KeyInvalidatedReason {
  /// Positive evidence that no key is stored, but a database exists.
  missing,

  /// The stored key can never be read again (Keystore alias gone or
  /// invalidated, tag failure, malformed blob), and a database exists.
  unusable,

  /// SQLite refused the key (SQLITE_NOTADB on the first page read),
  /// reported by [KeyBootstrap.reportRejected].
  rejectedBySqlite,
}

enum KeyUnavailableReason {
  /// The store answered "unavailable" (e.g. before first unlock on iOS, a
  /// transient Keystore error) or the database directory could not be read.
  transient,

  /// The bootstrap lease was not free within [bootstrapLeaseTimeout].
  leaseTimeout,
}

enum KeyStoreFailedReason {
  /// No usable random generator.
  generate,

  /// The store could not write, verify or delete the key.
  write,

  /// [KeyBootstrap.recreateAfterWipe] found database files still present.
  wipeIncomplete,
}

/// The result of [KeyBootstrap.obtain] and the follow-up calls. Never prints
/// key material.
sealed class KeyBootstrapOutcome {
  const KeyBootstrapOutcome();

  /// FU-050 diag code (emitted by T-021's logger; nothing is logged today).
  String get diagCode;

  /// The only diag fields: `{reason, platform, attempts}`.
  Map<String, Object> diagFields(String platform);
}

/// A key was found and a database exists. The lease is already released.
final class KeyReady extends KeyBootstrapOutcome {
  const KeyReady(this.key, {this.attempts = 1});

  final DbKeyMaterial key;
  final int attempts;

  @override
  String get diagCode => 'DB_KEY_READY';

  @override
  Map<String, Object> diagFields(String platform) => {
    'reason': 'found',
    'platform': platform,
    'attempts': attempts,
  };

  @override
  String toString() => 'KeyReady(attempts: $attempts)';
}

/// A new key is stored (read back and verified). No database exists. The
/// caller holds [lease]: create and verify the new database, then release.
final class KeyCreated extends KeyBootstrapOutcome {
  const KeyCreated(this.key, this.reason, this.lease);

  final DbKeyMaterial key;
  final KeyCreatedReason reason;
  final BootstrapLease lease;

  /// PO decision 2026-11-10 (Q2): after an orphan wipe the fresh Welcome
  /// shows a one-time line. The database owner (T-016) records this in the
  /// new database; the startup screen reads and clears it.
  bool get restoreNoticeDue => reason == KeyCreatedReason.afterWipe;

  @override
  String get diagCode => reason == KeyCreatedReason.rotatedNoDb
      ? 'DB_KEY_ROTATED'
      : 'DB_KEY_CREATED';

  @override
  Map<String, Object> diagFields(String platform) => {
    'reason': reason.name,
    'platform': platform,
    'attempts': 1,
  };

  @override
  String toString() => 'KeyCreated(${reason.name})';
}

/// A database exists but its key can't be used. Nothing was written or
/// deleted. The caller holds [lease]: wipe the database file set, spool, temp
/// files and guard config, then call [KeyBootstrap.recreateAfterWipe].
final class KeyInvalidated extends KeyBootstrapOutcome {
  const KeyInvalidated(this.reason, this.lease, {this.attempts = 1});

  final KeyInvalidatedReason reason;
  final BootstrapLease lease;
  final int attempts;

  @override
  String get diagCode => 'DB_KEY_INVALIDATED';

  @override
  Map<String, Object> diagFields(String platform) => {
    'reason': reason.name,
    'platform': platform,
    'attempts': attempts,
  };

  @override
  String toString() => 'KeyInvalidated(${reason.name})';
}

/// The key could not be read right now. Retry later; never wipe. The lease is
/// released.
final class KeyUnavailable extends KeyBootstrapOutcome {
  const KeyUnavailable(this.reason, {this.attempts = 0});

  final KeyUnavailableReason reason;
  final int attempts;

  @override
  String get diagCode => 'DB_KEY_UNAVAILABLE';

  @override
  Map<String, Object> diagFields(String platform) => {
    'reason': reason.name,
    'platform': platform,
    'attempts': attempts,
  };

  @override
  String toString() => 'KeyUnavailable(${reason.name}, attempts: $attempts)';
}

/// A key could not be generated, stored or verified. No database may be
/// created. The lease is released.
final class KeyStoreFailed extends KeyBootstrapOutcome {
  const KeyStoreFailed(this.reason);

  final KeyStoreFailedReason reason;

  @override
  String get diagCode => 'DB_KEY_STORE_FAILED';

  @override
  Map<String, Object> diagFields(String platform) => {
    'reason': reason.name,
    'platform': platform,
    'attempts': 1,
  };

  @override
  String toString() => 'KeyStoreFailed(${reason.name})';
}

/// Obtains K_db (design note §3). Stateless: every call asks the store.
final class KeyBootstrap {
  KeyBootstrap({
    required this._store,
    required this._files,
    required this._generator,
    this._leaseTimeout = bootstrapLeaseTimeout,
  });

  final SecretStore _store;
  final DbFileSet _files;
  final KeyGenerator _generator;
  final Duration _leaseTimeout;

  /// Reads or creates the key:
  ///
  /// | read        | no database                  | database present           |
  /// |-------------|------------------------------|----------------------------|
  /// | found       | rotate → KeyCreated(rotated) | KeyReady                   |
  /// | notFound    | create → KeyCreated(first)   | KeyInvalidated(missing)    |
  /// | unusable    | rotate → KeyCreated(rotated) | KeyInvalidated(unusable)   |
  /// | unavailable | KeyUnavailable(transient)    | KeyUnavailable(transient)  |
  Future<KeyBootstrapOutcome> obtain() => _withLease((lease) => _decide(lease));

  /// The T-016 hook: the open sequence's first page read failed with
  /// SQLITE_NOTADB (26) using [rejected]. Re-checks under the lease: if the
  /// stored key has changed meanwhile (another engine rotated it), returns
  /// [KeyReady] with the new key; if it is still [rejected] and a database
  /// exists, returns [KeyInvalidated] with [KeyInvalidatedReason.rejectedBySqlite].
  /// Any other SQLite error is transient and must not be reported here.
  Future<KeyBootstrapOutcome> reportRejected(DbKeyMaterial rejected) =>
      _withLease((lease) => _decide(lease, rejected: rejected));

  /// After an orphan wipe under [lease] (from [KeyInvalidated]): deletes the
  /// old key and stores a new one. Refuses ([KeyStoreFailed] with
  /// [KeyStoreFailedReason.wipeIncomplete]) while any database file remains.
  ///
  /// Unlike [obtain], this never releases [lease]: on any outcome the caller
  /// still holds it, so it can finish the wipe and retry (keeping the one-time
  /// restore notice, [KeyCreated.restoreNoticeDue]) or release it.
  Future<KeyBootstrapOutcome> recreateAfterWipe(BootstrapLease lease) async {
    if (lease.isReleased) throw StateError('DB_KEY_LEASE_RELEASED');
    return _guarded(lease, () async {
      if (await _files.anyExists()) {
        return const KeyStoreFailed(KeyStoreFailedReason.wipeIncomplete);
      }
      return _create(lease, KeyCreatedReason.afterWipe, deleteFirst: true);
    });
  }

  Future<KeyBootstrapOutcome> _withLease(
    Future<KeyBootstrapOutcome> Function(BootstrapLease lease) body,
  ) async {
    final SecretStoreLease raw;
    try {
      raw = await _store.acquireBootstrapLease(_leaseTimeout);
    } on SecretStoreException catch (e) {
      return KeyUnavailable(
        e.code == SecretStoreErrorCode.leaseTimeout
            ? KeyUnavailableReason.leaseTimeout
            : KeyUnavailableReason.transient,
      );
    }
    final lease = BootstrapLease._(_store, raw);
    final KeyBootstrapOutcome outcome;
    try {
      outcome = await _guarded(lease, () => body(lease));
    } on Object {
      await lease.release();
      rethrow;
    }
    await _releaseUnlessHeld(outcome, lease);
    return outcome;
  }

  /// Runs [body]; a store or file-system failure becomes a safe outcome.
  Future<KeyBootstrapOutcome> _guarded(
    BootstrapLease lease,
    Future<KeyBootstrapOutcome> Function() body,
  ) async {
    try {
      return await body();
    } on SecretStoreException catch (e) {
      return switch (e.code) {
        SecretStoreErrorCode.storeFailed => const KeyStoreFailed(
          KeyStoreFailedReason.write,
        ),
        SecretStoreErrorCode.leaseTimeout => const KeyUnavailable(
          KeyUnavailableReason.leaseTimeout,
        ),
        SecretStoreErrorCode.unavailable => const KeyUnavailable(
          KeyUnavailableReason.transient,
        ),
      };
    } on FileSystemException {
      return const KeyUnavailable(KeyUnavailableReason.transient);
    }
  }

  static Future<void> _releaseUnlessHeld(
    KeyBootstrapOutcome outcome,
    BootstrapLease lease,
  ) async {
    switch (outcome) {
      case KeyCreated() || KeyInvalidated():
        return; // the caller holds the lease
      case KeyReady() || KeyUnavailable() || KeyStoreFailed():
        await lease.release();
    }
  }

  Future<KeyBootstrapOutcome> _decide(
    BootstrapLease lease, {
    DbKeyMaterial? rejected,
  }) async {
    final dbPresent = await _files.anyExists();
    final read = await _store.read(SecretSlot.dbKey);
    switch (read.status) {
      case SecretStatus.found:
        final value = read.value!;
        if (!dbPresent) {
          wipeBytes(value);
          return _create(
            lease,
            KeyCreatedReason.rotatedNoDb,
            deleteFirst: true,
          );
        }
        if (value.length != dbKeyLength) {
          wipeBytes(value);
          return KeyInvalidated(
            KeyInvalidatedReason.unusable,
            lease,
            attempts: read.attempts,
          );
        }
        final key = DbKeyMaterial.copyOf(value);
        wipeBytes(value);
        if (rejected != null && key.sameKeyAs(rejected)) {
          key.zeroize();
          return KeyInvalidated(
            KeyInvalidatedReason.rejectedBySqlite,
            lease,
            attempts: read.attempts,
          );
        }
        return KeyReady(key, attempts: read.attempts);
      case SecretStatus.notFound:
        // NEGATIVE PROOF (a): writes a new key although a database exists.
        return _createIgnoringDb(lease);
      case SecretStatus.unusable:
        if (dbPresent) {
          return KeyInvalidated(
            KeyInvalidatedReason.unusable,
            lease,
            attempts: read.attempts,
          );
        }
        return _create(lease, KeyCreatedReason.rotatedNoDb, deleteFirst: true);
      case SecretStatus.unavailable:
        return KeyUnavailable(
          KeyUnavailableReason.transient,
          attempts: read.attempts,
        );
    }
  }

  Future<KeyBootstrapOutcome> _create(
    BootstrapLease lease,
    KeyCreatedReason reason, {
    required bool deleteFirst,
  }) async {
    final candidate = _generator.next();
    if (candidate == null || isDegenerateKey(candidate)) {
      if (candidate != null) wipeBytes(candidate);
      return const KeyStoreFailed(KeyStoreFailedReason.generate);
    }
    // Never delete or store a key while a database file exists (checked again
    // right before the first write; the lease keeps other engines out).
    if (await _files.anyExists()) {
      wipeBytes(candidate);
      return const KeyUnavailable(KeyUnavailableReason.transient);
    }
    if (deleteFirst) {
      try {
        await _store.delete(lease._lease, SecretSlot.dbKey);
      } on Object {
        wipeBytes(candidate);
        rethrow;
      }
    }
    final Uint8List stored;
    try {
      stored = await _store.createIfAbsent(
        lease._lease,
        SecretSlot.dbKey,
        candidate,
      );
    } finally {
      wipeBytes(candidate);
    }
    if (stored.length != dbKeyLength || isDegenerateKey(stored)) {
      wipeBytes(stored);
      return const KeyStoreFailed(KeyStoreFailedReason.write);
    }
    final key = DbKeyMaterial.copyOf(stored);
    wipeBytes(stored);
    return KeyCreated(key, reason, lease);
  }

  Future<KeyBootstrapOutcome> _createIgnoringDb(BootstrapLease lease) async {
    final candidate = _generator.next()!;
    final stored = await _store.createIfAbsent(
      lease._lease,
      SecretSlot.dbKey,
      candidate,
    );
    return KeyCreated(
      DbKeyMaterial.copyOf(stored),
      KeyCreatedReason.firstRun,
      lease,
    );
  }
}
