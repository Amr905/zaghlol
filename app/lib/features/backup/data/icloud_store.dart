// T-151 (design note §2–§8): encrypted backups in the user's iCloud
// container, `Documents/Backups/`, through the native ICloudBackupHostApi.
// Same names and safety rules as the Drive store (T-150):
// - nothing is ever overwritten: every backup is a new file;
// - pruning runs only with a just-verified upload as `protect` that iCloud
//   reports as **uploaded** to the server, after a complete listing that
//   still shows it; any doubt → no deletes;
// - only our backup names are touched (native refuses any other name too);
// - pruning keeps every file created at or after `protect` and the newest
//   `keep`, so two phones pruning at once keep the newest backup.
//
// Nothing here logs.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;

import '../../../core/platform/icloud_api.g.dart';
import 'drive_store.dart'
    show
        LocalBackupFile,
        backupFileName,
        isBackupFileName,
        isPartialFileName,
        maxBackupFileBytes;
import 'icloud_backup_exception.dart';

/// The native calls, as a port (tests use an in-memory fake).
abstract interface class ICloudFiles {
  Future<bool> isAvailable();
  Future<BackupMeta> upload(String path, String name);
  Future<List<BackupMeta>> list();
  Future<String> download(String name);
  Future<void> delete(String name);
}

/// Maps a native error code to ours; unknown → io (fail closed).
ICloudBackupErrorCode iCloudCodeOf(String code) => switch (code) {
  'ICLOUD_UNAVAILABLE' => ICloudBackupErrorCode.unavailable,
  'TIMEOUT' => ICloudBackupErrorCode.timeout,
  'NOT_FOUND' => ICloudBackupErrorCode.notFound,
  'ALREADY_EXISTS' ||
  'UPLOAD_UNVERIFIED' => ICloudBackupErrorCode.uploadUnverified,
  'TOO_LARGE' => ICloudBackupErrorCode.tooLarge,
  'INVALID_ARGUMENT' => ICloudBackupErrorCode.notOurFile,
  _ => ICloudBackupErrorCode.io,
};

/// [ICloudFiles] over Pigeon. Every failure becomes a code-only
/// [ICloudBackupException] (the native message is never read).
final class PigeonICloudFiles implements ICloudFiles {
  PigeonICloudFiles({ICloudBackupHostApi? api})
    : _api = api ?? ICloudBackupHostApi();

  final ICloudBackupHostApi _api;

  Future<T> _call<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PlatformException catch (e) {
      throw ICloudBackupException(iCloudCodeOf(e.code));
    } on ICloudBackupException {
      rethrow;
    } on Object {
      throw ICloudBackupException(ICloudBackupErrorCode.io);
    }
  }

  @override
  Future<bool> isAvailable() => _call(_api.isAvailable);

  @override
  Future<BackupMeta> upload(String path, String name) =>
      _call(() => _api.upload(path, name));

  @override
  Future<List<BackupMeta>> list() => _call(_api.list);

  @override
  Future<String> download(String name) => _call(() => _api.download(name));

  @override
  Future<void> delete(String name) => _call(() => _api.delete(name));
}

final RegExp _finalName = RegExp(
  r'^zaghlol-backup-([0-9]{1,16})-([0-9]{1,16})\.zaghlol\.enc$',
);

/// One of our finished backups in iCloud. [labelSeq] and [labelCreatedAtMs]
/// come from the file name: **not authenticated** until the restore decrypts
/// chunk 0 (T-148 security I-3). [createdAtMs] is the file-system creation
/// time from the creating phone's clock.
final class ICloudBackupEntry {
  const ICloudBackupEntry({
    required this.name,
    required this.sizeBytes,
    required this.createdAtMs,
    required this.isUploaded,
    required this.isDownloaded,
    required this.quotaExceeded,
    required this.uploadFailed,
    required this.labelSeq,
    required this.labelCreatedAtMs,
    this.md5,
  });

  /// Null when [m] is not one of our finished backups.
  static ICloudBackupEntry? fromMeta(BackupMeta m) {
    final match = _finalName.firstMatch(m.name);
    if (match == null) return null;
    return ICloudBackupEntry(
      name: m.name,
      sizeBytes: m.sizeBytes,
      createdAtMs: m.createdAtMs,
      isUploaded: m.isUploaded,
      isDownloaded: m.isDownloaded,
      quotaExceeded: m.quotaExceeded,
      uploadFailed: m.uploadFailed,
      md5: m.md5,
      labelSeq: int.parse(match.group(1)!),
      labelCreatedAtMs: int.parse(match.group(2)!),
    );
  }

  final String name;
  final int? sizeBytes;
  final int? createdAtMs;
  final bool isUploaded;
  final bool isDownloaded;
  final bool quotaExceeded;
  final bool uploadFailed;
  final String? md5;
  final int labelSeq;
  final int labelCreatedAtMs;

  @override
  String toString() =>
      'ICloudBackupEntry(seq: $labelSeq, uploaded: $isUploaded)';
}

/// What a prune did. [skipped]: nothing deleted because the state could not
/// be proven. [failure]: the first error, after which pruning stopped.
final class ICloudPruneReport {
  const ICloudPruneReport({
    required this.deleted,
    required this.skipped,
    this.failure,
  });

  final int deleted;
  final bool skipped;
  final ICloudBackupErrorCode? failure;

  @override
  String toString() =>
      'ICloudPruneReport(deleted: $deleted, skipped: $skipped, '
      'failure: $failure)';
}

/// The deletion plan (design note §5); pure. Returns null when nothing may
/// be deleted ([protect] not proven uploaded and unchanged).
List<String>? planICloudPrune({
  required List<BackupMeta> listing,
  required ICloudBackupEntry protect,
  required int keep,
  required Duration partialAge,
}) {
  if (keep < 1) throw ArgumentError('PRUNE_KEEP');
  final mine = listing.where((f) => f.name == protect.name).toList();
  if (mine.length != 1) return null;
  final p = mine.single;
  final protectTime = p.createdAtMs;
  if (protectTime == null ||
      p.sizeBytes == null ||
      p.sizeBytes != protect.sizeBytes ||
      !p.isUploaded ||
      p.quotaExceeded ||
      p.uploadFailed) {
    return null;
  }
  // Undated files can't be ordered: never deleted.
  final dated = [
    for (final f in listing)
      if (isBackupFileName(f.name) && f.createdAtMs != null) f,
  ]..sort(_newestFirst);
  final kept = <String>{protect.name};
  for (final f in dated.take(keep)) {
    kept.add(f.name);
  }
  final out = <String>[];
  for (final f in dated) {
    if (kept.contains(f.name)) continue;
    // Created at or after our uploaded backup (e.g. another phone's): kept.
    if (f.createdAtMs! >= protectTime) continue;
    out.add(f.name);
  }
  final sweepBefore = protectTime - partialAge.inMilliseconds;
  for (final f in listing) {
    final t = f.createdAtMs;
    if (isPartialFileName(f.name) && t != null && t <= sweepBefore) {
      out.add(f.name);
    }
  }
  return out;
}

int _newestFirst(BackupMeta a, BackupMeta b) {
  final c = b.createdAtMs!.compareTo(a.createdAtMs!);
  return c != 0 ? c : b.name.compareTo(a.name);
}

final class ICloudBackupStore {
  ICloudBackupStore(
    this._files, {
    this.metadataTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 11),
    this.partialAge = const Duration(hours: 24),
  });

  final ICloudFiles _files;
  final Duration metadataTimeout;
  final Duration downloadTimeout;
  final Duration partialAge;

  bool _busy = false;

  /// Upload time limit: 60 s plus 1 s per 25 KB (as Drive).
  static Duration uploadTimeout(int length) =>
      Duration(seconds: 60 + length ~/ 25000);

  Future<T> _locked<T>(Future<T> Function() body) async {
    if (_busy) throw ICloudBackupException(ICloudBackupErrorCode.busy);
    _busy = true;
    try {
      return await body();
    } finally {
      _busy = false;
    }
  }

  Future<T> _timed<T>(Future<T> f, Duration limit) => f.timeout(
    limit,
    onTimeout: () => throw ICloudBackupException(ICloudBackupErrorCode.timeout),
  );

  /// True when iCloud can be used now. Never throws.
  Future<bool> isAvailable() async {
    try {
      return await _timed(_files.isAvailable(), metadataTimeout);
    } on Object {
      return false;
    }
  }

  Future<void> _requireAvailable() async {
    if (!await isAvailable()) {
      throw ICloudBackupException(ICloudBackupErrorCode.unavailable);
    }
  }

  Future<List<BackupMeta>> _listAll() async {
    final all = await _timed(_files.list(), metadataTimeout);
    if (all.length > maxICloudListed) {
      throw ICloudBackupException(ICloudBackupErrorCode.listTooLong);
    }
    return [
      for (final f in all)
        if (isBackupFileName(f.name) || isPartialFileName(f.name)) f,
    ];
  }

  static List<ICloudBackupEntry> _entries(List<BackupMeta> all) {
    final entries = [for (final f in all) ?ICloudBackupEntry.fromMeta(f)];
    entries.sort((a, b) {
      final ta = a.createdAtMs;
      final tb = b.createdAtMs;
      if (ta == null || tb == null) {
        return ta == null ? (tb == null ? 0 : 1) : -1;
      }
      final c = tb.compareTo(ta);
      return c != 0 ? c : b.name.compareTo(a.name);
    });
    return entries;
  }

  /// Our finished backups, newest first (undated last).
  Future<List<ICloudBackupEntry>> list() => _locked(() async {
    await _requireAvailable();
    return _entries(await _listAll());
  });

  /// Copies [local] into iCloud (native: `.partial`, read back, move) and
  /// checks the stored size and MD5 against it. Not yet "complete": see
  /// [waitUploaded].
  Future<ICloudBackupEntry> upload(LocalBackupFile local) => _locked(() async {
    if (local.length < 1 || local.length > maxBackupFileBytes) {
      throw ICloudBackupException(ICloudBackupErrorCode.tooLarge);
    }
    final name = backupFileName(local.seq, local.createdAtMs);
    await _requireAvailable();
    final meta = await _timed(
      _files.upload(local.file.path, name),
      uploadTimeout(local.length),
    );
    final entry = ICloudBackupEntry.fromMeta(meta);
    if (entry == null ||
        meta.name != name ||
        meta.sizeBytes != local.length ||
        meta.md5 == null ||
        meta.md5!.toLowerCase() != local.md5Hex.toLowerCase()) {
      throw ICloudBackupException(ICloudBackupErrorCode.uploadUnverified);
    }
    return entry;
  });

  /// Polls the listing until iCloud reports [entry] uploaded with its size.
  /// Returns the uploaded entry, or null when [timeout] passes first (or the
  /// state stays unknown). A quota error on [entry] → quotaExceeded.
  Future<ICloudBackupEntry?> waitUploaded(
    ICloudBackupEntry entry, {
    Duration timeout = const Duration(seconds: 120),
    Duration interval = const Duration(seconds: 3),
  }) => _locked(() async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        for (final f in await _listAll()) {
          if (f.name != entry.name) continue;
          if (f.quotaExceeded) {
            throw ICloudBackupException(ICloudBackupErrorCode.quotaExceeded);
          }
          if (f.isUploaded && f.sizeBytes == entry.sizeBytes) {
            return ICloudBackupEntry.fromMeta(f);
          }
        }
      } on ICloudBackupException catch (e) {
        if (e.reason == ICloudBackupErrorCode.quotaExceeded) rethrow;
        // Unknown state: keep waiting; never treated as uploaded.
      }
      if (!DateTime.now().add(interval).isBefore(deadline)) return null;
      await Future<void>.delayed(interval);
    }
  });

  /// Deletes our older backups beyond [keep], keeping [protect] (a backup
  /// [upload] verified and [waitUploaded] saw uploaded), everything created
  /// at or after it and the newest [keep]. Any doubt → nothing is deleted.
  Future<ICloudPruneReport> prune({
    required ICloudBackupEntry protect,
    required int keep,
  }) => _locked(() async {
    final List<BackupMeta> listing;
    try {
      await _requireAvailable();
      listing = await _listAll();
    } on ICloudBackupException catch (e) {
      return ICloudPruneReport(deleted: 0, skipped: true, failure: e.reason);
    }
    final plan = planICloudPrune(
      listing: listing,
      protect: protect,
      keep: keep,
      partialAge: partialAge,
    );
    if (plan == null) return const ICloudPruneReport(deleted: 0, skipped: true);
    var deleted = 0;
    for (final name in plan) {
      try {
        await _timed(_files.delete(name), metadataTimeout);
        deleted++;
      } on ICloudBackupException catch (e) {
        if (e.reason == ICloudBackupErrorCode.notFound) continue;
        return ICloudPruneReport(
          deleted: deleted,
          skipped: false,
          failure: e.reason,
        );
      }
    }
    return ICloudPruneReport(deleted: deleted, skipped: false);
  });

  /// The content of [entry] (one of ours), capped at its listed size. Native
  /// downloads it and copies it to the temp directory; the copy is deleted
  /// when the stream ends or is cancelled. The store stays busy until then.
  Stream<List<int>> download(ICloudBackupEntry entry) async* {
    if (!isBackupFileName(entry.name)) {
      throw ICloudBackupException(ICloudBackupErrorCode.notOurFile);
    }
    final size = entry.sizeBytes;
    if (size == null || size < 1 || size > maxBackupFileBytes) {
      throw ICloudBackupException(ICloudBackupErrorCode.tooLarge);
    }
    if (_busy) throw ICloudBackupException(ICloudBackupErrorCode.busy);
    _busy = true;
    File? copy;
    try {
      await _requireAvailable();
      final path = await _timed(_files.download(entry.name), downloadTimeout);
      // Only the native download copy (ciphertext) is ever read or deleted.
      if (!path.contains('/zaghlol_backup_download/') ||
          !path.endsWith('.zaghlol.enc')) {
        throw ICloudBackupException(ICloudBackupErrorCode.io);
      }
      copy = File(path);
      var received = 0;
      try {
        await for (final data in copy.openRead()) {
          received += data.length;
          if (received > size) {
            throw ICloudBackupException(ICloudBackupErrorCode.corruptDownload);
          }
          yield data;
        }
      } on FileSystemException {
        throw ICloudBackupException(ICloudBackupErrorCode.io);
      }
      if (received != size) {
        throw ICloudBackupException(ICloudBackupErrorCode.corruptDownload);
      }
    } finally {
      if (copy != null) {
        try {
          await copy.delete();
        } on FileSystemException {
          // Native clears its download directory before the next download.
        }
      }
      _busy = false;
    }
  }

  /// Deletes one of our backups on the user's explicit, confirmed request
  /// (e.g. old-passphrase backups, T-148 Q1). Not for retention.
  Future<void> delete(ICloudBackupEntry entry) => _locked(() async {
    if (!isBackupFileName(entry.name)) {
      throw ICloudBackupException(ICloudBackupErrorCode.notOurFile);
    }
    await _requireAvailable();
    final current = await _listAll();
    if (!current.any((f) => f.name == entry.name)) {
      throw ICloudBackupException(ICloudBackupErrorCode.notFound);
    }
    try {
      await _timed(_files.delete(entry.name), metadataTimeout);
    } on ICloudBackupException catch (e) {
      if (e.reason != ICloudBackupErrorCode.notFound) rethrow;
    }
  });
}
