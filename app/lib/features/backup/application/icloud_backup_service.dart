// T-151 (design note §3–§7): "back up to iCloud" and "restore from iCloud".
// The twin of DriveBackupService (T-150), with one more step: iCloud
// uploads asynchronously, so pruning waits until iCloud reports the new file
// uploaded to the server.
//
// backupNow: availability → list (quota check, seq) → snapshot stream
//            (T-149) → encrypted temp file → verifyFile + MD5 in one read
//            (T-148 §6) → verified copy into iCloud (.partial → move) → store
//            seq → wait until uploaded → prune.
// A failure or doubt at any step before "uploaded" deletes nothing in
// iCloud. The temp file holds ciphertext only and is deleted at the end of
// every run.
//
// Nothing here logs.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;

import '../crypto/backup_cipher.dart';
import '../crypto/backup_crypto_exception.dart';
import '../crypto/backup_format.dart';
import '../crypto/backup_keys.dart';
import '../crypto/backup_stream.dart' show readHeader;
import '../crypto/byte_reader.dart';
import '../data/drive_store.dart' show LocalBackupFile, maxBackupFileBytes;
import '../data/icloud_backup_exception.dart';
import '../data/icloud_store.dart';
import '../data/secure_state_seq_store.dart';
import 'backup_snapshot_service.dart';
import 'drive_backup_service.dart' show maxLabelSeq;

/// The iCloud upload staging directory under the app's temp directory. Not
/// the Drive one: each service wipes its own staging directory.
const String iCloudUploadDirName = 'zaghlol_backup_upload_icloud';

final class ICloudBackupOutcome {
  const ICloudBackupOutcome({
    required this.entry,
    required this.uploaded,
    required this.prune,
    required this.seqStored,
  });

  /// The verified backup in the container.
  final ICloudBackupEntry entry;

  /// iCloud reported the new backup uploaded within the wait. False: it is
  /// still uploading, nothing was pruned ([prune] is skipped), and a later
  /// run prunes the leftovers.
  final bool uploaded;
  final ICloudPruneReport prune;

  /// False when the uploaded `seq` could not be stored (the next run takes
  /// it from the listing).
  final bool seqStored;

  @override
  String toString() =>
      'ICloudBackupOutcome(uploaded: $uploaded, $prune, seqStored: $seqStored)';
}

final class ICloudBackupService {
  ICloudBackupService({
    required this._snapshot,
    required this._cipher,
    required this._store,
    required this._seq,
    required this._tempDirectory,
    this.uploadWait = const Duration(seconds: 120),
    this.uploadPoll = const Duration(seconds: 3),
    Random? random,
  }) : _random = random ?? Random.secure();

  final BackupSnapshotService _snapshot;
  final BackupCipher _cipher;
  final ICloudBackupStore _store;
  final BackupSeqStore _seq;
  final Future<Directory> Function() _tempDirectory;
  final Duration uploadWait;
  final Duration uploadPoll;
  final Random _random;

  bool _busy = false;

  /// True when iCloud can be used now. When false, the caller shows
  /// `backup_settings_errorIcloud` and offers Google Drive.
  Future<bool> isAvailable() => _store.isAvailable();

  /// Backs up now and keeps the newest [keep] backups (T-152 chooses: Free
  /// 1, Gold 5). iCloud off → `ICloudBackupException(unavailable)`.
  Future<ICloudBackupOutcome> backupNow(
    BackupKeys keys, {
    required int keep,
    required BackupPlatform platform,
    required String appVersion,
    int chunkSize = defaultChunkSize,
  }) async {
    if (keep < 1) throw ArgumentError('PRUNE_KEEP');
    if (_busy) throw ICloudBackupException(ICloudBackupErrorCode.busy);
    _busy = true;
    Directory? dir;
    try {
      final listed = await _store.list();
      // A backup iCloud refused for lack of space: don't stack another full
      // copy in the container until the user frees space.
      if (listed.any((e) => e.quotaExceeded)) {
        throw ICloudBackupException(ICloudBackupErrorCode.quotaExceeded);
      }
      final seq = await _nextSeq(listed);
      dir = await _resetDir();
      final local = await _writeVerified(
        dir,
        keys,
        seq: seq,
        platform: platform,
        appVersion: appVersion,
        chunkSize: chunkSize,
      );
      final entry = await _store.upload(local);
      var seqStored = true;
      try {
        await _seq.write(seq);
      } on Object {
        seqStored = false;
      }
      final uploaded = await _store.waitUploaded(
        entry,
        timeout: uploadWait,
        interval: uploadPoll,
      );
      if (uploaded == null) {
        return ICloudBackupOutcome(
          entry: entry,
          uploaded: false,
          prune: const ICloudPruneReport(deleted: 0, skipped: true),
          seqStored: seqStored,
        );
      }
      final prune = await _store.prune(protect: uploaded, keep: keep);
      return ICloudBackupOutcome(
        entry: uploaded,
        uploaded: true,
        prune: prune,
        seqStored: seqStored,
      );
    } finally {
      await _sweep(dir);
      _busy = false;
    }
  }

  /// Our finished backups in iCloud, newest first (labels unauthenticated).
  Future<List<ICloudBackupEntry>> list() => _store.list();

  /// Restores [entry] with [passphrase] (T-149 restore; FU-139 lists the
  /// caller's duties). The live database is unchanged on any failure.
  Future<RestoreOutcome> restore(
    ICloudBackupEntry entry,
    String passphrase,
  ) async {
    if (_busy) throw ICloudBackupException(ICloudBackupErrorCode.busy);
    _busy = true;
    try {
      return await _snapshot.restore(_store.download(entry), passphrase);
    } finally {
      _busy = false;
    }
  }

  Future<int> _nextSeq(List<ICloudBackupEntry> listed) async {
    int? stored;
    try {
      stored = await _seq.read();
    } on Object {
      stored = null; // The listing still gives a floor.
    }
    var top = stored ?? 0;
    for (final e in listed) {
      if (e.labelSeq <= maxLabelSeq && e.labelSeq > top) top = e.labelSeq;
    }
    return top + 1;
  }

  Future<Directory> _resetDir() async {
    try {
      final d = Directory(
        '${(await _tempDirectory()).path}/$iCloudUploadDirName',
      );
      // Only our own ciphertext staging files from an earlier run live here.
      if (await d.exists()) await d.delete(recursive: true);
      await d.create(recursive: true);
      return d;
    } on FileSystemException {
      throw ICloudBackupException(ICloudBackupErrorCode.io);
    }
  }

  static Future<void> _sweep(Directory? d) async {
    if (d == null) return;
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } on FileSystemException {
      // Swept at the next run (and by the orphan wipe of the temp dir).
    }
  }

  Future<LocalBackupFile> _writeVerified(
    Directory dir,
    BackupKeys keys, {
    required int seq,
    required BackupPlatform platform,
    required String appVersion,
    required int chunkSize,
  }) async {
    final name = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File('${dir.path}/$name.zaghlol.enc');
    var written = 0;
    final sink = file.openWrite();
    try {
      await for (final data in _snapshot.write(
        keys,
        seq: seq,
        platform: platform,
        appVersion: appVersion,
        chunkSize: chunkSize,
      )) {
        written += data.length;
        if (written > maxBackupFileBytes) {
          throw ICloudBackupException(ICloudBackupErrorCode.tooLarge);
        }
        sink.add(data);
      }
      await sink.flush();
    } on FileSystemException {
      throw ICloudBackupException(ICloudBackupErrorCode.io);
    } finally {
      try {
        await sink.close();
      } on FileSystemException {
        // The verify read below fails on a broken file.
      }
    }

    // One read of the file on disk: verify every chunk and hash the bytes.
    final digest = _DigestSink();
    final md5In = hash.md5.startChunkedConversion(digest);
    var read = 0;
    try {
      await _cipher.verifyFile(
        file.openRead().map((b) {
          read += b.length;
          md5In.add(b);
          return b;
        }),
        keys,
      );
    } finally {
      md5In.close();
    }
    if (read != written) {
      throw BackupCryptoException(BackupCryptoErrorCode.corruptData);
    }
    final reader = ByteReader(file.openRead());
    final BackupHeader header;
    try {
      header = (await readHeader(reader)).$2;
    } finally {
      await reader.cancel();
    }
    if (header.meta.seq != seq) {
      throw BackupCryptoException(BackupCryptoErrorCode.corruptHeader);
    }
    return LocalBackupFile(
      file: file,
      length: written,
      md5Hex: digest.value!.toString(),
      seq: seq,
      createdAtMs: header.createdAtMs,
      platform: header.meta.platform.name,
      schemaVersion: header.meta.schemaVersion,
    );
  }
}

final class _DigestSink implements Sink<hash.Digest> {
  hash.Digest? value;

  @override
  void add(hash.Digest data) => value = data;

  @override
  void close() {}
}
