// T-150 (design note §1, §7): the narrow Drive v3 port the backup store
// needs, and its googleapis adapter. Every call is pinned to the hidden
// `appDataFolder` space; nothing here can address a file in the user's
// visible Drive (the token only carries `drive.appdata` anyway). Errors are
// mapped to DriveBackupException codes; server messages are dropped. Nothing
// here logs.

import 'dart:async';
import 'dart:io' show HttpException, SocketException;

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_backup_exception.dart';

/// The OAuth scope: the hidden per-app folder only (D-11).
const String driveAppDataScope = drive.DriveApi.driveAppdataScope;

/// The Drive space and parent alias of the hidden app folder.
const String appDataFolder = 'appDataFolder';

/// One file's metadata as Drive reports it. [createdTime] is the server's
/// clock (never the device's). [appProperties] are our own labels and are
/// unauthenticated (T-148 security I-3).
final class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.size,
    required this.md5,
    required this.createdTime,
    this.appProperties = const {},
  });

  final String id;
  final String name;

  /// Null when Drive did not report it (never for a finished blob upload).
  final int? size;
  final String? md5;
  final DateTime? createdTime;
  final Map<String, String> appProperties;

  @override
  String toString() => 'DriveFile(size: $size)';
}

final class DriveFilePage {
  const DriveFilePage(this.files, this.nextPageToken);

  final List<DriveFile> files;
  final String? nextPageToken;
}

/// The Drive operations the backup store uses, all inside `appDataFolder`.
/// Implementations throw only DriveBackupException.
abstract interface class DriveFiles {
  /// One page of non-trashed files in `appDataFolder`.
  Future<DriveFilePage> list({String? pageToken});

  /// Creates [name] in `appDataFolder` from [media] ([length] bytes) with a
  /// resumable upload: Drive creates nothing until the last byte arrives.
  Future<DriveFile> create({
    required String name,
    required Map<String, String> appProperties,
    required Stream<List<int>> media,
    required int length,
  });

  /// Renames [id] (metadata only; content and createdTime unchanged).
  Future<DriveFile> rename(String id, String newName);

  /// The file's content.
  Stream<List<int>> download(String id);

  /// Deletes [id] permanently (app-folder files can't be trashed).
  Future<void> delete(String id);

  /// Releases the HTTP client.
  void close();
}

const String _fileFields = 'id,name,size,md5Checksum,createdTime,appProperties';

/// The Drive v3 adapter. [client] adds the bearer token (see drive_auth).
final class GoogleapisDriveFiles implements DriveFiles {
  GoogleapisDriveFiles(this._client) : _api = drive.DriveApi(_client);

  final http.Client _client;
  final drive.DriveApi _api;

  static const int pageSize = 100;

  static DriveFile _of(drive.File f) => DriveFile(
    id: f.id ?? '',
    name: f.name ?? '',
    size: int.tryParse(f.size ?? ''),
    md5: f.md5Checksum,
    createdTime: f.createdTime?.toUtc(),
    appProperties: Map.unmodifiable(f.appProperties ?? const {}),
  );

  @override
  Future<DriveFilePage> list({String? pageToken}) => guardDrive(() async {
    final r = await _api.files.list(
      spaces: appDataFolder,
      q: "'$appDataFolder' in parents and trashed = false",
      pageSize: pageSize,
      pageToken: pageToken,
      $fields: 'nextPageToken,files($_fileFields)',
    );
    return DriveFilePage([
      for (final f in r.files ?? const <drive.File>[]) _of(f),
    ], r.nextPageToken);
  });

  @override
  Future<DriveFile> create({
    required String name,
    required Map<String, String> appProperties,
    required Stream<List<int>> media,
    required int length,
  }) => guardDrive(() async {
    final f = await _api.files.create(
      drive.File(
        name: name,
        parents: const [appDataFolder],
        appProperties: appProperties,
        mimeType: 'application/octet-stream',
      ),
      uploadMedia: drive.Media(media, length),
      uploadOptions: drive.ResumableUploadOptions(),
      $fields: _fileFields,
    );
    return _of(f);
  });

  @override
  Future<DriveFile> rename(String id, String newName) => guardDrive(() async {
    final f = await _api.files.update(
      drive.File(name: newName),
      id,
      $fields: _fileFields,
    );
    return _of(f);
  });

  @override
  Stream<List<int>> download(String id) async* {
    final media = await guardDrive(
      () async => await _api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media,
    );
    try {
      yield* media.stream;
    } on DriveBackupException {
      rethrow;
    } on Object catch (e) {
      throw DriveBackupException(classifyDriveError(e));
    }
  }

  @override
  Future<void> delete(String id) => guardDrive(() => _api.files.delete(id));

  @override
  void close() => _client.close();
}

/// Runs [call] and maps any failure to a DriveBackupException.
Future<T> guardDrive<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DriveBackupException {
    rethrow;
  } on Object catch (e) {
    throw DriveBackupException(classifyDriveError(e));
  }
}

/// Maps a googleapis / http / io error to a code (design note §7). Unknown
/// → serverError (never a reason to delete anything).
DriveBackupErrorCode classifyDriveError(Object e) {
  if (e is drive.DetailedApiRequestError) {
    final reasons = {for (final d in e.errors) d.reason};
    final status = e.status;
    if (status == 401) return DriveBackupErrorCode.authExpired;
    if (status == 404) return DriveBackupErrorCode.notFound;
    if (reasons.contains('storageQuotaExceeded') ||
        reasons.contains('quotaExceeded')) {
      return DriveBackupErrorCode.quotaExceeded;
    }
    if (status == 429 ||
        reasons.contains('rateLimitExceeded') ||
        reasons.contains('userRateLimitExceeded')) {
      return DriveBackupErrorCode.rateLimited;
    }
    if (status == 403) return DriveBackupErrorCode.authorizationDenied;
    return DriveBackupErrorCode.serverError;
  }
  if (e is SocketException ||
      e is HttpException ||
      e is http.ClientException ||
      e is TimeoutException) {
    return DriveBackupErrorCode.network;
  }
  return DriveBackupErrorCode.serverError;
}
