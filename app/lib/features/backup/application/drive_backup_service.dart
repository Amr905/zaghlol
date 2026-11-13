// T-150 (design note §3–§6): "back up to Drive" and "restore from Drive".
//
// backupNow: list (auth first, cheap) → seq → snapshot stream (T-149) →
//            encrypted temp file → verifyFile + MD5 in one read (T-148 §6)
//            → verified upload (temp name → rename) → store seq → prune.
// Pruning runs only after the upload is verified complete; a failure at any
// earlier step deletes nothing on Drive. The temp file holds ciphertext only
// and is deleted at the end of every run (and swept at the next start).
//
// Pure Dart (no Flutter). Nothing here logs.

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
import '../data/drive_backup_exception.dart';
import '../data/drive_store.dart';
import '../data/secure_state_seq_store.dart';
import 'backup_snapshot_service.dart';

/// The upload staging directory under the app's temp directory.
const String backupUploadDirName = 'zaghlol_backup_upload';

/// The highest `seq` label taken from Drive (labels are unauthenticated: a
/// huge one must not push the counter out of range).
const int maxLabelSeq = 1 << 40;

final class DriveBackupOutcome {
  const DriveBackupOutcome({
    required this.entry,
    required this.prune,
    required this.seqStored,
  });

  /// The verified, renamed backup.
  final DriveBackupEntry entry;
  final PruneReport prune;

  /// False when the uploaded `seq` could not be stored (the next run takes
  /// it from the listing).
  final bool seqStored;

  @override
  String toString() => 'DriveBackupOutcome($prune, seqStored: $seqStored)';
}

final class DriveBackupService {
  DriveBackupService({
    required this._snapshot,
    required this._cipher,
    required this._store,
    required this._seq,
    required this._tempDirectory,
    Random? random,
  }) : _random = random ?? Random.secure();

  final BackupSnapshotService _snapshot;
  final BackupCipher _cipher;
  final DriveBackupStore _store;
  final BackupSeqStore _seq;
  final Future<Directory> Function() _tempDirectory;
  final Random _random;

  bool _busy = false;

  /// Backs up now and keeps the newest [keep] backups (T-152 chooses: Free
  /// 1, Gold 5). [interactive]: the user is present for sign-in/consent.
  Future<DriveBackupOutcome> backupNow(
    BackupKeys keys, {
    required int keep,
    required BackupPlatform platform,
    required String appVersion,
    bool interactive = true,
    int chunkSize = defaultChunkSize,
  }) async {
    if (keep < 1) throw ArgumentError('PRUNE_KEEP');
    if (_busy) throw DriveBackupException(DriveBackupErrorCode.busy);
    _busy = true;
    Directory? dir;
    try {
      final listed = await _store.list(interactive: interactive);
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
      final entry = await _store.upload(local, interactive: interactive);
      var seqStored = true;
      try {
        await _seq.write(seq);
      } on Object {
        seqStored = false;
      }
      final prune = await _store.prune(
        protect: entry,
        keep: keep,
        interactive: interactive,
      );
      return DriveBackupOutcome(
        entry: entry,
        prune: prune,
        seqStored: seqStored,
      );
    } finally {
      await _sweep(dir);
      _busy = false;
    }
  }

  /// Our finished backups on Drive, newest first (labels unauthenticated).
  Future<List<DriveBackupEntry>> list({bool interactive = true}) =>
      _store.list(interactive: interactive);

  /// Restores [entry] with [passphrase] (T-149 restore; FU-139 lists the
  /// caller's duties). The live database is unchanged on any failure.
  Future<RestoreOutcome> restore(
    DriveBackupEntry entry,
    String passphrase, {
    bool interactive = true,
  }) async {
    if (_busy) throw DriveBackupException(DriveBackupErrorCode.busy);
    _busy = true;
    try {
      return await _snapshot.restore(
        _store.download(entry, interactive: interactive),
        passphrase,
      );
    } finally {
      _busy = false;
    }
  }

  Future<int> _nextSeq(List<DriveBackupEntry> listed) async {
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
        '${(await _tempDirectory()).path}/$backupUploadDirName',
      );
      // Only our own ciphertext staging files from an earlier run live here.
      if (await d.exists()) await d.delete(recursive: true);
      await d.create(recursive: true);
      return d;
    } on FileSystemException {
      throw DriveBackupException(DriveBackupErrorCode.io);
    }
  }

  static Future<void> _sweep(Directory? d) async {
    if (d == null) return;
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } on FileSystemException {
      // Swept at the next start (and by the orphan wipe of the temp dir).
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
          throw DriveBackupException(DriveBackupErrorCode.tooLarge);
        }
        sink.add(data);
      }
      await sink.flush();
    } on FileSystemException {
      throw DriveBackupException(DriveBackupErrorCode.io);
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
