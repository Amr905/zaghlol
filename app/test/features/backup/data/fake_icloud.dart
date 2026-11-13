// T-151: an in-memory iCloud container (`Documents/Backups/`) behaving like
// the native ICloudBackupHost: our names only, never overwrites, reports
// size/MD5 on upload, and uploads to "the server" only after a number of
// listings (iCloud uploads asynchronously). No account, no device.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:zaghlol/core/platform/icloud_api.g.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart'
    show isBackupFileName, isPartialFileName;
import 'package:zaghlol/features/backup/data/icloud_backup_exception.dart';
import 'package:zaghlol/features/backup/data/icloud_store.dart';

final class FakeICloudFile {
  FakeICloudFile(this.bytes, this.createdAtMs);

  Uint8List bytes;
  int createdAtMs;
  bool uploaded = false;
  int listsSeen = 0;
  bool quota = false;
}

final class FakeICloud implements ICloudFiles {
  FakeICloud(this.downloadRoot, {int start = 1731500000000}) : _now = start;

  final Directory downloadRoot;
  final Map<String, FakeICloudFile> files = {};
  int _now;
  bool available = true;

  /// Listings after which a new file counts as uploaded; null = never.
  int? uploadAfterLists = 0;

  /// The next new file is refused by iCloud for lack of space.
  bool quotaOnNext = false;

  /// The next upload reports a different MD5 than the bytes it got.
  bool corruptNextUpload = false;

  /// Throws before an operation runs ('list', 'upload', 'download',
  /// 'delete'); may also await (two-actor tests).
  FutureOr<void> Function(String op, String? name)? before;

  final List<String> calls = [];
  final List<String> deleted = [];

  List<String> get names => files.keys.toList()..sort();

  int _tick() => _now += 60000;

  void seed(String name, List<int> bytes, {int? createdAtMs, bool up = true}) {
    files[name] = FakeICloudFile(
      Uint8List.fromList(bytes),
      createdAtMs ?? _tick(),
    )..uploaded = up;
  }

  BackupMeta _meta(String name, FakeICloudFile f, {String? md5}) => BackupMeta(
    name: name,
    sizeBytes: f.bytes.length,
    createdAtMs: f.createdAtMs,
    isUploaded: f.uploaded,
    isDownloaded: true,
    quotaExceeded: f.quota,
    uploadFailed: false,
    md5: md5,
  );

  Future<void> _enter(String op, String? name) async {
    calls.add(op);
    await before?.call(op, name);
    if (!available) {
      throw ICloudBackupException(ICloudBackupErrorCode.unavailable);
    }
  }

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BackupMeta> upload(String path, String name) async {
    await _enter('upload', name);
    if (!isBackupFileName(name)) {
      throw ICloudBackupException(ICloudBackupErrorCode.notOurFile);
    }
    if (files.containsKey(name) || files.containsKey('$name.partial')) {
      throw ICloudBackupException(ICloudBackupErrorCode.uploadUnverified);
    }
    final bytes = await File(path).readAsBytes();
    final f = FakeICloudFile(bytes, _tick())..quota = quotaOnNext;
    quotaOnNext = false;
    files[name] = f;
    var md5 = c.md5.convert(bytes).toString();
    if (corruptNextUpload) {
      corruptNextUpload = false;
      md5 = c.md5.convert([...bytes, 0]).toString();
    }
    return _meta(name, f, md5: md5);
  }

  @override
  Future<List<BackupMeta>> list() async {
    await _enter('list', null);
    final out = <BackupMeta>[];
    for (final e in files.entries) {
      final f = e.value;
      final after = uploadAfterLists;
      if (!f.uploaded && !f.quota && after != null && f.listsSeen++ >= after) {
        f.uploaded = true;
      }
      if (isBackupFileName(e.key) || isPartialFileName(e.key)) {
        out.add(_meta(e.key, f));
      }
    }
    return out;
  }

  @override
  Future<String> download(String name) async {
    await _enter('download', name);
    final f = files[name];
    if (f == null) throw ICloudBackupException(ICloudBackupErrorCode.notFound);
    final dir = Directory('${downloadRoot.path}/zaghlol_backup_download');
    await dir.create(recursive: true);
    final out = File('${dir.path}/${calls.length}.zaghlol.enc');
    await out.writeAsBytes(f.bytes);
    return out.path;
  }

  @override
  Future<void> delete(String name) async {
    await _enter('delete', name);
    if (!isBackupFileName(name) && !isPartialFileName(name)) {
      throw ICloudBackupException(ICloudBackupErrorCode.notOurFile);
    }
    if (files.remove(name) == null) {
      throw ICloudBackupException(ICloudBackupErrorCode.notFound);
    }
    deleted.add(name);
  }
}
