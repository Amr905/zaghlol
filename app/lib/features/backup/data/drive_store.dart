// T-150 (design note §2–§7): encrypted backups in the user's hidden Drive
// app folder. Names, listing, verified upload (temp name → checks → rename),
// retention pruning, download for restore and explicit delete.
//
// Never destroy data on doubt (self-check §1):
// - nothing is ever overwritten: every backup is a new file;
// - pruning runs only with a just-verified upload as `protect`, after a full,
//   successful listing that still shows it; any doubt → no deletes;
// - only files with our backup names (from an appDataFolder listing) are
//   touched; the token itself only reaches the app folder;
// - pruning keeps every file created at or after `protect` (another phone's
//   newer upload), so two phones pruning at once keep the newest backup.
//
// Pure Dart (no Flutter). Nothing here logs.

import 'dart:async';
import 'dart:io';

import 'drive_auth.dart';
import 'drive_backup_exception.dart';
import 'drive_files.dart';

/// Upper bound for a backup file, enforced on upload and download.
const int maxBackupFileBytes = 1 << 30;

/// Listing cap: pages of [GoogleapisDriveFiles.pageSize].
const int maxListPages = 20;

final RegExp _finalName = RegExp(
  r'^zaghlol-backup-([0-9]{1,16})-([0-9]{1,16})\.zaghlol\.enc$',
);
final RegExp _partialName = RegExp(
  r'^zaghlol-backup-[0-9]{1,16}-[0-9]{1,16}\.zaghlol\.enc\.partial$',
);

/// The final name of backup [seq] made at [createdAtMs].
String backupFileName(int seq, int createdAtMs) {
  if (seq < 0 || createdAtMs < 0) throw ArgumentError('BACKUP_NAME');
  final name = 'zaghlol-backup-$seq-$createdAtMs.zaghlol.enc';
  if (!_finalName.hasMatch(name)) throw ArgumentError('BACKUP_NAME');
  return name;
}

/// The in-flight name of [finalName].
String partialFileName(String finalName) => '$finalName.partial';

bool isBackupFileName(String name) => _finalName.hasMatch(name);
bool isPartialFileName(String name) => _partialName.hasMatch(name);

/// One of our finished backups. [labelSeq], [labelCreatedAtMs],
/// [labelPlatform] and [labelSchemaVersion] come from the file name and
/// `appProperties`: file metadata, **not authenticated** until the restore
/// decrypts chunk 0 (T-148 security I-3). [serverCreatedAt] is Drive's clock.
final class DriveBackupEntry {
  const DriveBackupEntry({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.md5,
    required this.serverCreatedAt,
    required this.labelSeq,
    required this.labelCreatedAtMs,
    this.labelPlatform,
    this.labelSchemaVersion,
  });

  /// Null when [f] is not one of our finished backups.
  static DriveBackupEntry? fromFile(DriveFile f) {
    final m = _finalName.firstMatch(f.name);
    if (m == null || f.id.isEmpty) return null;
    final platform = f.appProperties['platform'];
    final schema = int.tryParse(f.appProperties['schema'] ?? '');
    return DriveBackupEntry(
      id: f.id,
      name: f.name,
      sizeBytes: f.size,
      md5: f.md5,
      serverCreatedAt: f.createdTime,
      labelSeq: int.parse(m.group(1)!),
      labelCreatedAtMs: int.parse(m.group(2)!),
      labelPlatform: platform == 'android' || platform == 'ios'
          ? platform
          : null,
      labelSchemaVersion: schema != null && schema >= 0 && schema < 1 << 20
          ? schema
          : null,
    );
  }

  final String id;
  final String name;
  final int? sizeBytes;
  final String? md5;
  final DateTime? serverCreatedAt;
  final int labelSeq;
  final int labelCreatedAtMs;
  final String? labelPlatform;
  final int? labelSchemaVersion;

  @override
  String toString() => 'DriveBackupEntry(seq: $labelSeq)';
}

/// A local, already encrypted and verified backup file (design note §3).
final class LocalBackupFile {
  const LocalBackupFile({
    required this.file,
    required this.length,
    required this.md5Hex,
    required this.seq,
    required this.createdAtMs,
    required this.platform,
    required this.schemaVersion,
  });

  final File file;
  final int length;

  /// Lowercase hex, as Drive reports `md5Checksum`.
  final String md5Hex;
  final int seq;
  final int createdAtMs;
  final String platform;
  final int schemaVersion;
}

/// What a prune did. [skipped]: nothing deleted because the state could not
/// be proven (listing failed, `protect` missing or changed). [failure]: the
/// first delete error, after which pruning stopped.
final class PruneReport {
  const PruneReport({
    required this.deleted,
    required this.skipped,
    this.failure,
  });

  final int deleted;
  final bool skipped;
  final DriveBackupErrorCode? failure;

  @override
  String toString() =>
      'PruneReport(deleted: $deleted, skipped: $skipped, failure: $failure)';
}

/// The deletion plan (design note §4); pure, so it is tested on its own.
/// Returns null when nothing may be deleted ([protect] not proven).
List<String>? planPrune({
  required List<DriveFile> listing,
  required DriveBackupEntry protect,
  required int keep,
  required Duration partialAge,
}) {
  if (keep < 1) throw ArgumentError('PRUNE_KEEP');
  final protectTime = protect.serverCreatedAt;
  if (protectTime == null) return null;
  final mine = listing.where((f) => f.id == protect.id).toList();
  if (mine.length != 1) return null;
  final p = mine.single;
  if (p.name != protect.name ||
      p.size == null ||
      p.size != protect.sizeBytes ||
      p.md5 == null ||
      p.md5 != protect.md5) {
    return null;
  }
  final finals = [
    for (final f in listing)
      if (isBackupFileName(f.name) && f.id.isNotEmpty) f,
  ];
  // Undated files can't be ordered: never deleted.
  final dated = finals.where((f) => f.createdTime != null).toList()
    ..sort((a, b) {
      final c = b.createdTime!.compareTo(a.createdTime!);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
  final kept = <String>{protect.id};
  for (final f in dated.take(keep)) {
    kept.add(f.id);
  }
  final out = <String>[];
  for (final f in dated) {
    if (kept.contains(f.id)) continue;
    // Created at or after our verified upload (e.g. another phone's): kept.
    if (!f.createdTime!.isBefore(protectTime)) continue;
    out.add(f.id);
  }
  final sweepBefore = protectTime.subtract(partialAge);
  for (final f in listing) {
    final t = f.createdTime;
    if (isPartialFileName(f.name) &&
        f.id.isNotEmpty &&
        f.id != protect.id &&
        t != null &&
        !t.isAfter(sweepBefore)) {
      out.add(f.id);
    }
  }
  return out;
}

final class _Session {
  _Session(this._connector, this._interactive);

  final DriveConnector _connector;
  final bool _interactive;
  DriveFiles? _files;
  String? _token;
  bool _refreshed = false;

  Future<T> call<T>(Future<T> Function(DriveFiles files) op) async {
    while (true) {
      if (_files == null) {
        final (files, token) = await _connector.connect(
          interactive: _interactive,
        );
        _files = files;
        _token = token;
      }
      try {
        return await op(_files!);
      } on DriveBackupException catch (e) {
        if (e.reason != DriveBackupErrorCode.authExpired) rethrow;
        if (_refreshed) {
          throw DriveBackupException(DriveBackupErrorCode.authorizationDenied);
        }
        _refreshed = true;
        await _connector.refused(_token!);
        close();
      }
    }
  }

  void close() {
    _files?.close();
    _files = null;
    _token = null;
  }
}

final class DriveBackupStore {
  DriveBackupStore(
    this._connector, {
    this.metadataTimeout = const Duration(seconds: 30),
    this.downloadIdleTimeout = const Duration(seconds: 60),
    this.partialAge = const Duration(hours: 24),
  });

  final DriveConnector _connector;
  final Duration metadataTimeout;
  final Duration downloadIdleTimeout;
  final Duration partialAge;

  bool _busy = false;

  /// Upload time limit: 60 s plus 1 s per 25 KB.
  static Duration uploadTimeout(int length) =>
      Duration(seconds: 60 + length ~/ 25000);

  Future<T> _locked<T>(
    bool interactive,
    Future<T> Function(_Session s) body,
  ) async {
    if (_busy) throw DriveBackupException(DriveBackupErrorCode.busy);
    _busy = true;
    final session = _Session(_connector, interactive);
    try {
      return await body(session);
    } finally {
      session.close();
      _busy = false;
    }
  }

  Future<T> _timed<T>(Future<T> f, Duration limit) => f.timeout(
    limit,
    onTimeout: () => throw DriveBackupException(DriveBackupErrorCode.network),
  );

  Future<List<DriveFile>> _listAll(_Session s) async {
    final all = <DriveFile>[];
    String? token;
    final seen = <String>{};
    for (var page = 0; page < maxListPages; page++) {
      final p = await s.call(
        (f) => _timed(f.list(pageToken: token), metadataTimeout),
      );
      all.addAll(p.files);
      token = p.nextPageToken;
      if (token == null || token.isEmpty) return all;
      if (!seen.add(token)) break;
    }
    throw DriveBackupException(DriveBackupErrorCode.listTooLong);
  }

  /// Our finished backups, newest first by Drive's clock (undated last).
  Future<List<DriveBackupEntry>> list({bool interactive = false}) =>
      _locked(interactive, (s) async {
        final entries = [
          for (final f in await _listAll(s)) ?DriveBackupEntry.fromFile(f),
        ];
        entries.sort((a, b) {
          final ta = a.serverCreatedAt;
          final tb = b.serverCreatedAt;
          if (ta == null || tb == null) {
            return ta == null ? (tb == null ? 0 : 1) : -1;
          }
          final c = tb.compareTo(ta);
          return c != 0 ? c : b.id.compareTo(a.id);
        });
        return entries;
      });

  /// Uploads [local] under a `.partial` name, checks Drive's size and MD5
  /// against it, then renames it to its final name and checks again. On a
  /// mismatch the partial is deleted (it is ours and provably wrong) and
  /// uploadUnverified is thrown. Never touches any other file.
  Future<DriveBackupEntry> upload(
    LocalBackupFile local, {
    bool interactive = false,
  }) => _locked(interactive, (s) async {
    if (local.length < 1 || local.length > maxBackupFileBytes) {
      throw DriveBackupException(DriveBackupErrorCode.tooLarge);
    }
    final name = backupFileName(local.seq, local.createdAtMs);
    final partial = partialFileName(name);
    final md5 = local.md5Hex.toLowerCase();
    final created = await s.call(
      (f) => _timed(
        f.create(
          name: partial,
          appProperties: {
            'zglb': '1',
            'platform': local.platform,
            'schema': '${local.schemaVersion}',
          },
          media: local.file.openRead(),
          length: local.length,
        ),
        uploadTimeout(local.length),
      ),
    );
    if (created.id.isEmpty ||
        created.name != partial ||
        created.size != local.length ||
        created.md5?.toLowerCase() != md5) {
      if (created.id.isNotEmpty && created.name == partial) {
        try {
          await s.call((f) => _timed(f.delete(created.id), metadataTimeout));
        } on DriveBackupException {
          // Left as a partial: swept by a later prune (design note §4).
        }
      }
      throw DriveBackupException(DriveBackupErrorCode.uploadUnverified);
    }
    final renamed = await s.call(
      (f) => _timed(f.rename(created.id, name), metadataTimeout),
    );
    if (renamed.id != created.id ||
        renamed.name != name ||
        renamed.size != local.length ||
        renamed.md5?.toLowerCase() != md5) {
      throw DriveBackupException(DriveBackupErrorCode.uploadUnverified);
    }
    final entry = DriveBackupEntry.fromFile(renamed);
    if (entry == null) {
      throw DriveBackupException(DriveBackupErrorCode.uploadUnverified);
    }
    return entry;
  });

  /// Deletes our older backups beyond [keep], keeping [protect] (a backup
  /// [upload] just verified), everything created at or after it and the
  /// newest [keep]. Any doubt about the listing → nothing is deleted.
  Future<PruneReport> prune({
    required DriveBackupEntry protect,
    required int keep,
    bool interactive = false,
  }) => _locked(interactive, (s) async {
    final List<DriveFile> listing;
    try {
      listing = await _listAll(s);
    } on DriveBackupException catch (e) {
      return PruneReport(deleted: 0, skipped: true, failure: e.reason);
    }
    final plan = planPrune(
      listing: listing,
      protect: protect,
      keep: keep,
      partialAge: partialAge,
    );
    if (plan == null) return const PruneReport(deleted: 0, skipped: true);
    var deleted = 0;
    for (final id in plan) {
      try {
        await s.call((f) => _timed(f.delete(id), metadataTimeout));
        deleted++;
      } on DriveBackupException catch (e) {
        if (e.reason == DriveBackupErrorCode.notFound) continue;
        return PruneReport(deleted: deleted, skipped: false, failure: e.reason);
      }
    }
    return PruneReport(deleted: deleted, skipped: false);
  });

  /// The content of [entry] (one of ours), capped at its listed size. The
  /// store stays busy until the stream ends or is cancelled.
  Stream<List<int>> download(
    DriveBackupEntry entry, {
    bool interactive = false,
  }) async* {
    if (!isBackupFileName(entry.name) || entry.id.isEmpty) {
      throw DriveBackupException(DriveBackupErrorCode.notOurFile);
    }
    final size = entry.sizeBytes;
    if (size == null || size < 1 || size > maxBackupFileBytes) {
      throw DriveBackupException(DriveBackupErrorCode.tooLarge);
    }
    if (_busy) throw DriveBackupException(DriveBackupErrorCode.busy);
    _busy = true;
    final session = _Session(_connector, interactive);
    try {
      // Connect (and refresh once) before the first byte.
      final files = await session.call((f) async => f);
      var received = 0;
      try {
        await for (final data
            in files
                .download(entry.id)
                .timeout(
                  downloadIdleTimeout,
                  onTimeout: (sink) => sink.addError(
                    DriveBackupException(DriveBackupErrorCode.network),
                  ),
                )) {
          received += data.length;
          if (received > size) {
            throw DriveBackupException(DriveBackupErrorCode.corruptDownload);
          }
          yield data;
        }
      } on DriveBackupException {
        rethrow;
      } on Object catch (e) {
        throw DriveBackupException(classifyDriveError(e));
      }
      if (received != size) {
        throw DriveBackupException(DriveBackupErrorCode.corruptDownload);
      }
    } finally {
      session.close();
      _busy = false;
    }
  }

  /// Deletes one of our backups on the user's explicit, confirmed request
  /// (e.g. old-passphrase backups, T-148 Q1). Not for retention.
  Future<void> delete(DriveBackupEntry entry, {bool interactive = false}) =>
      _locked(interactive, (s) async {
        if (!isBackupFileName(entry.name) || entry.id.isEmpty) {
          throw DriveBackupException(DriveBackupErrorCode.notOurFile);
        }
        // The id must still carry that name in our folder right now.
        final current = await _listAll(s);
        if (!current.any((f) => f.id == entry.id && f.name == entry.name)) {
          throw DriveBackupException(DriveBackupErrorCode.notOurFile);
        }
        try {
          await s.call((f) => _timed(f.delete(entry.id), metadataTimeout));
        } on DriveBackupException catch (e) {
          if (e.reason != DriveBackupErrorCode.notFound) rethrow;
        }
      });
}
