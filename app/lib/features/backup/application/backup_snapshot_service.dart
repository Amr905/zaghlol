// T-149 (design note §3–§5): backup snapshot and restore swap.
//
// write():   live DB → snapshot under K_snap (work dir) → contents v1 →
//            BackupCipher.encrypt. Reads the live database only.
// restore(): BackupCipher.open (EC-26 before the KDF) → contents → snapshot
//            file (encrypted bytes only) → `done` → checks → stage under this
//            device's K_db (migrate older) → carry device tables → ONE
//            SQLite transaction replaces the live content → store K_bk.
//
// Never destroy data on doubt (self-check §1): nothing writes the live
// database before the swap, and the swap is a single SQLite write
// transaction (a crash before its commit leaves the old database). Work
// files are encrypted derived copies in `<temp>/zaghlol_backup_work/`,
// swept at the start and end of every operation (and by the orphan wipe,
// which clears the temp directory). One operation at a time per service.
//
// Pure Dart (no Flutter); the SQLite steps run through [BackupIsolateRunner]
// (a background isolate in the app). Nothing here logs.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/db/app_database.dart' show appSchemaVersion;
import '../../../core/db/db_file_set.dart';
import '../../../core/db/key_bootstrap.dart' show DbKeyMaterial;
import '../crypto/backup_cipher.dart';
import '../crypto/backup_crypto_exception.dart';
import '../crypto/backup_format.dart';
import '../crypto/backup_keys.dart';
import '../data/secure_state_key_slot_store.dart';
import 'backup_contents.dart';
import 'backup_snapshot_exception.dart';
import 'snapshot_db.dart';

/// Runs a SQLite step. The app uses [isolateRunner]; tests run inline.
typedef BackupIsolateRunner = Future<T> Function<T>(Future<T> Function() task);

/// `Isolate.run`: the task must capture only sendable values.
Future<T> isolateRunner<T>(Future<T> Function() task) => Isolate.run(task);

/// Runs [task] on this isolate.
Future<T> inlineRunner<T>(Future<T> Function() task) => task();

/// The work directory name under the app's temp directory.
const String backupWorkDirName = 'zaghlol_backup_work';

/// What a completed restore reports (authenticated header values).
final class RestoreOutcome {
  RestoreOutcome({
    required this.createdAtMs,
    required this.seq,
    required this.schemaVersion,
    required this.platform,
    required this.appVersion,
    required this.keyStored,
  });

  final int createdAtMs;
  final int seq;

  /// The backup's schema version (≤ the app's; older ones were migrated).
  final int schemaVersion;
  final BackupPlatform platform;
  final String appVersion;

  /// False when the restored K_bk could not be stored after the swap: the
  /// data is restored; the next backup asks for the passphrase
  /// (keyMismatch → recoverWithPassphrase).
  final bool keyStored;

  @override
  String toString() => 'RestoreOutcome(schema: $schemaVersion)';
}

final class BackupSnapshotService {
  BackupSnapshotService({
    required this._cipher,
    required this._files,
    required this._tempDirectory,
    required this._liveKey,
    this._runner = isolateRunner,
    DateTime Function()? clock,
    this.onStep,
    this.swapPagesPerStep = -1,
    this.onSwapStep,
  }) : _clock = clock ?? DateTime.now;

  final BackupCipher _cipher;
  final DbFileSet _files;
  final Future<Directory> Function() _tempDirectory;
  final Future<DbKeyMaterial> Function() _liveKey;
  final BackupIsolateRunner _runner;
  final DateTime Function() _clock;

  /// Test seam: called after each named step; throwing simulates a failure
  /// (or a process death) right there.
  final void Function(String step)? onStep;

  /// Test seams for the swap (the app copies in one step, no callback).
  final int swapPagesPerStep;
  final void Function()? onSwapStep;

  bool _busy = false;

  void _step(String name) => onStep?.call(name);

  void _acquire() {
    if (_busy) throw BackupSnapshotException(BackupSnapshotErrorCode.busy);
    _busy = true;
  }

  Future<Directory> _resetWork() async {
    try {
      final work = Directory(
        '${(await _tempDirectory()).path}/$backupWorkDirName',
      );
      // Only encrypted, derived copies live here (a crashed earlier run's
      // leftovers); never live data. Safe to sweep under the lock.
      if (await work.exists()) await work.delete(recursive: true);
      await work.create(recursive: true);
      return work;
    } on FileSystemException {
      throw BackupSnapshotException(BackupSnapshotErrorCode.io);
    }
  }

  static Future<void> _sweep(Directory? work) async {
    if (work == null) return;
    try {
      if (await work.exists()) await work.delete(recursive: true);
    } on FileSystemException {
      // Swept again at the next start (and by the orphan wipe).
    }
  }

  Future<DbKeyMaterial> _liveKeyOrThrow() async {
    try {
      return await _liveKey();
    } on Object {
      throw BackupSnapshotException(BackupSnapshotErrorCode.liveUnavailable);
    }
  }

  static Future<DbKeyMaterial> _snapKey(
    BackupKeys keys,
    List<int> fileId,
  ) async {
    final s = await keys.snapshotKey(fileId);
    try {
      return DbKeyMaterial.copyOf(s.bytes);
    } finally {
      s.zeroize();
    }
  }

  // ---------------------------------------------------------------- backup

  /// The encrypted backup file as a stream (design note §3). The caller
  /// writes it (T-150: encrypted temp + verify-after-write) and deletes
  /// partial output on error. Work files are deleted when the stream ends,
  /// fails or is cancelled. [seq]: the stored counter + 1 (T-150).
  Stream<List<int>> write(
    BackupKeys keys, {
    required int seq,
    required BackupPlatform platform,
    required String appVersion,
    int chunkSize = defaultChunkSize,
  }) async* {
    _acquire();
    Directory? work;
    try {
      work = await _resetWork();
      final fileId = _cipher.newFileId();
      final kSnap = await _snapKey(keys, fileId);
      final SnapshotFacts facts;
      final snapFile = File('${work.path}/snap.db');
      try {
        final kDb = await _liveKeyOrThrow();
        try {
          final live = _files.mainFile;
          facts = await _runner(
            () => buildSnapshot(
              live: live,
              liveKey: kDb,
              out: snapFile,
              snapKey: kSnap,
            ),
          );
        } finally {
          kDb.zeroize();
        }
      } finally {
        kSnap.zeroize();
      }
      _step('snapshot');
      final settings = encodeSettings(facts.settings);
      final manifest = SnapshotManifest(
        contentsVersion: contentsVersionV1,
        schemaVersion: facts.schemaVersion,
        snapshotBytes: facts.bytes,
        settingsBytes: settings.length,
        tables: facts.tables,
      ).encode();
      yield* _cipher.encrypt(
        keys,
        HeaderMeta(
          seq: seq,
          schemaVersion: facts.schemaVersion,
          platform: platform,
          appVersion: appVersion,
        ),
        encodeContents(
          snapshot: snapFile,
          snapshotBytes: facts.bytes,
          settings: settings,
          manifest: manifest,
        ),
        chunkSize: chunkSize,
        fileId: fileId,
      );
      _step('encrypted');
    } finally {
      await _sweep(work);
      _busy = false;
    }
  }

  // --------------------------------------------------------------- restore

  /// Restores [file] with [passphrase] over the live database (design note
  /// §4). Throws BackupCryptoException (newerSchema / wrongPassphrase /
  /// corruptData / …) or BackupSnapshotException; in every failure case the
  /// live database is unchanged. On success the caller re-opens the database
  /// (`ref.invalidate(appDatabaseProvider)`) and runs the catalog sync; the
  /// re-grant prompt is due through `db_meta restore_regrant_due`.
  Future<RestoreOutcome> restore(
    Stream<List<int>> file,
    String passphrase,
  ) async {
    _acquire();
    Directory? work;
    try {
      work = await _resetWork();
      final session = await _cipher.open(
        file,
        passphrase,
        maxSchemaVersion: appSchemaVersion,
      );
      final snapFile = File('${work.path}/restore-snapshot.db');
      final DecodedContents contents;
      try {
        _step('unlocked');
        contents = await decodeContents(session.plaintext, snapFile);
      } on Object {
        await session.dispose();
        // The session's own error (corruptData, …) explains a broken stream
        // better than the reader's io.
        try {
          await session.done;
        } on BackupCryptoException catch (c) {
          if (c.reason != BackupCryptoErrorCode.io) rethrow;
        } on Object {
          // Fall through to the decoder's error.
        }
        rethrow;
      }
      final result = await session.done;
      final keys = result.keys;
      try {
        _step('decrypted');
        final manifest = SnapshotManifest.decode(contents.manifestBytes);
        if (manifest.contentsVersion != result.header.meta.contentsVersion ||
            manifest.schemaVersion != result.schemaVersion ||
            manifest.snapshotBytes != contents.snapshotBytes ||
            manifest.settingsBytes != contents.settingsBytes.length) {
          throw BackupSnapshotException(
            BackupSnapshotErrorCode.corruptContents,
          );
        }
        final kSnap = await _snapKey(keys, result.header.fileId);
        try {
          final kDb = await _liveKeyOrThrow();
          try {
            await _restoreInto(
              work: work,
              snapFile: snapFile,
              kSnap: kSnap,
              kDb: kDb,
              headerSchema: result.schemaVersion,
              manifest: manifest,
              settings: contents.settings,
              slotCbor: keys.slot.toCbor(),
            );
          } finally {
            kDb.zeroize();
          }
        } finally {
          kSnap.zeroize();
        }
        await _sweep(work);
        var keyStored = true;
        try {
          await _cipher.storeRestoredKey(keys);
        } on BackupCryptoException {
          keyStored = false;
        }
        _step('keyStored');
        return RestoreOutcome(
          createdAtMs: result.createdAtMs,
          seq: result.seq,
          schemaVersion: result.schemaVersion,
          platform: result.platform,
          appVersion: result.appVersion,
          keyStored: keyStored,
        );
      } finally {
        keys.zeroize();
      }
    } finally {
      await _sweep(work);
      _busy = false;
    }
  }

  Future<void> _restoreInto({
    required Directory work,
    required File snapFile,
    required DbKeyMaterial kSnap,
    required DbKeyMaterial kDb,
    required int headerSchema,
    required SnapshotManifest manifest,
    required Map<String, String> settings,
    required Uint8List slotCbor,
  }) async {
    // Locals only in the closures: they cross to an isolate.
    final stage = File('${work.path}/restore-stage.db');
    final live = _files.mainFile;
    final slot = slotCbor;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    final pages = swapPagesPerStep;
    final onSwap = onSwapStep;
    await _runner(
      () => stageRestore(
        snap: snapFile,
        snapKey: kSnap,
        stage: stage,
        dbKey: kDb,
        headerSchemaVersion: headerSchema,
        manifest: manifest,
        settings: settings,
      ),
    );
    _step('staged');
    await _runner(
      () => carryDeviceState(
        live: live,
        stage: stage,
        dbKey: kDb,
        slotCbor: slot,
        slotStateKey: backupKeySlotStateKey,
        nowMs: now,
      ),
    );
    _step('carried');
    await _runner(
      () => swapIntoLive(
        stage: stage,
        live: live,
        dbKey: kDb,
        pagesPerStep: pages,
        onStep: onSwap,
      ),
    );
    _step('swapped');
  }
}
