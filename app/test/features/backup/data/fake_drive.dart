// T-150: an in-memory Google Drive app folder for tests. No network, no
// credentials. The server clock ticks one minute per created file; hooks
// inject failures (network, partial upload, wrong bytes, 401, list errors).

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:zaghlol/features/backup/data/drive_auth.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/data/drive_files.dart';

final class FakeBlob {
  FakeBlob(this.meta, this.bytes);

  DriveFile meta;
  Uint8List bytes;
}

final class FakeDrive {
  FakeDrive({DateTime? start}) : _now = start ?? DateTime.utc(2026, 11, 13);

  final Map<String, FakeBlob> files = {};
  DateTime _now;
  int _ids = 0;
  int _tokens = 0;

  /// Tokens Drive answers 401 for.
  final Set<String> expired = {};
  final List<String> refused = [];
  final List<String> deleted = [];
  final List<String> calls = [];

  /// Throws before an operation runs ('list', 'create', 'rename',
  /// 'download', 'delete'); may also await (two-actor tests).
  FutureOr<void> Function(String op, String? id)? before;

  /// The next create stops after this many bytes with a network error and
  /// creates nothing (an interrupted resumable upload).
  int? dropUploadAfter;

  /// The next create stores these bytes altered (Drive's MD5 then differs).
  bool corruptNextUpload = false;

  /// The next rename answers with a different name (did not land).
  bool renameLies = false;

  /// Bytes the next download appends (or removes when negative).
  int downloadSkew = 0;

  /// Page size of list (to exercise paging).
  int pageSize = 100;

  /// List answers this many pages before ending (null: real end).
  bool endlessPages = false;

  DateTime tick() => _now = _now.add(const Duration(minutes: 1));

  String newToken() => 'tok${_tokens++}';

  /// Puts a file straight into the folder (another app version, a foreign
  /// file, a stale partial).
  DriveFile seed(
    String name,
    List<int> bytes, {
    DateTime? createdTime,
    Map<String, String> appProperties = const {},
    bool dated = true,
  }) {
    final id = 'id${_ids++}';
    final b = Uint8List.fromList(bytes);
    final meta = DriveFile(
      id: id,
      name: name,
      size: b.length,
      md5: c.md5.convert(b).toString(),
      createdTime: dated ? (createdTime ?? tick()) : null,
      appProperties: appProperties,
    );
    files[id] = FakeBlob(meta, b);
    return meta;
  }

  List<String> get names => [for (final f in files.values) f.meta.name]..sort();
}

final class FakeDriveFiles implements DriveFiles {
  FakeDriveFiles(this.drive, this.token);

  final FakeDrive drive;
  final String token;
  bool closed = false;

  Future<void> _enter(String op, [String? id]) async {
    if (closed) throw StateError('closed');
    drive.calls.add(op);
    await drive.before?.call(op, id);
    if (drive.expired.contains(token)) {
      throw DriveBackupException(DriveBackupErrorCode.authExpired);
    }
  }

  @override
  Future<DriveFilePage> list({String? pageToken}) async {
    await _enter('list');
    final all = drive.files.values.map((f) => f.meta).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final start = int.tryParse(pageToken ?? '0') ?? 0;
    final end = start + drive.pageSize;
    final page = all.sublist(
      start.clamp(0, all.length),
      end.clamp(0, all.length),
    );
    final next = drive.endlessPages
        ? '${start + 1}'
        : (end < all.length ? '$end' : null);
    return DriveFilePage(page, next);
  }

  @override
  Future<DriveFile> create({
    required String name,
    required Map<String, String> appProperties,
    required Stream<List<int>> media,
    required int length,
  }) async {
    await _enter('create');
    final b = BytesBuilder();
    final drop = drive.dropUploadAfter;
    drive.dropUploadAfter = null;
    await for (final d in media) {
      b.add(d);
      if (drop != null && b.length >= drop) {
        throw DriveBackupException(DriveBackupErrorCode.network);
      }
    }
    final bytes = b.takeBytes();
    if (bytes.length != length) {
      throw DriveBackupException(DriveBackupErrorCode.serverError);
    }
    if (drive.corruptNextUpload) {
      drive.corruptNextUpload = false;
      bytes[bytes.length ~/ 2] ^= 1;
    }
    return drive.seed(name, bytes, appProperties: appProperties);
  }

  @override
  Future<DriveFile> rename(String id, String newName) async {
    await _enter('rename', id);
    final f = drive.files[id];
    if (f == null) throw DriveBackupException(DriveBackupErrorCode.notFound);
    final lie = drive.renameLies;
    drive.renameLies = false;
    if (!lie) {
      f.meta = DriveFile(
        id: f.meta.id,
        name: newName,
        size: f.meta.size,
        md5: f.meta.md5,
        createdTime: f.meta.createdTime,
        appProperties: f.meta.appProperties,
      );
    }
    return f.meta;
  }

  @override
  Stream<List<int>> download(String id) async* {
    await _enter('download', id);
    final f = drive.files[id];
    if (f == null) throw DriveBackupException(DriveBackupErrorCode.notFound);
    var bytes = f.bytes;
    if (drive.downloadSkew > 0) {
      bytes = Uint8List.fromList([
        ...bytes,
        ...List.filled(drive.downloadSkew, 0),
      ]);
    } else if (drive.downloadSkew < 0) {
      bytes = Uint8List.sublistView(
        bytes,
        0,
        bytes.length + drive.downloadSkew,
      );
    }
    for (var i = 0; i < bytes.length; i += 40000) {
      yield Uint8List.sublistView(
        bytes,
        i,
        i + 40000 > bytes.length ? bytes.length : i + 40000,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    await _enter('delete', id);
    if (drive.files.remove(id) == null) {
      throw DriveBackupException(DriveBackupErrorCode.notFound);
    }
    drive.deleted.add(id);
  }

  @override
  void close() => closed = true;
}

final class FakeConnector implements DriveConnector {
  FakeConnector(this.drive);

  final FakeDrive drive;
  DriveBackupErrorCode? connectError;
  final List<bool> interactiveCalls = [];

  @override
  Future<(DriveFiles, String)> connect({required bool interactive}) async {
    interactiveCalls.add(interactive);
    final e = connectError;
    if (e != null) throw DriveBackupException(e);
    final t = drive.newToken();
    return (FakeDriveFiles(drive, t), t);
  }

  @override
  Future<void> refused(String token) async => drive.refused.add(token);
}
