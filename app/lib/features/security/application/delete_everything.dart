// T-166: "Delete everything" (FR-ONB-08, EC-29, EC-69, D-55, R4-8;
// security-model §7; design note in docs/04-tasks/tasks/T-166.md).
//
// Order: the key slots go first after the database is closed (crypto-shred),
// so a crash at any later step leaves nothing readable; a marker file makes
// the next launch run the local steps again. The backend call runs last, on a
// throwaway client over an in-memory copy of the install credentials, and the
// local wipe never waits for it.
//
// Nothing here logs: no path, token, key or error text leaves this file. The
// report holds constant step ids only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/crypto/secret_store.dart';
import '../../../core/db/db_file_set.dart';
import '../../../core/db/orphan_wipe.dart';

/// The install credentials the backend delete needs, read before the wipe
/// and kept in memory only.
final class InstallCredentials {
  InstallCredentials({required this.installId, required this.installToken});

  final String installId;
  final String installToken;

  @override
  String toString() => 'InstallCredentials(<redacted>)';
}

/// The native part of the wipe (capture host `wipeLocalData`). Throws when
/// something could not be deleted; the other parts still ran.
abstract interface class NativeWipe {
  Future<void> wipeLocalData();
}

/// The resume marker: an empty file whose presence at launch means a wipe
/// did not finish. It holds no data.
final class WipeMarker {
  WipeMarker(this.file);

  /// The marker in [appSupport] (the parent of the database directory).
  factory WipeMarker.inDirectory(Directory appSupport) =>
      WipeMarker(File('${appSupport.path}/$fileName'));

  static const String fileName = 'wipe_pending';

  final File file;

  Future<bool> exists() => file.exists();

  Future<void> set() async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [], flush: true);
  }

  Future<void> clear() async {
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

/// Step ids, constant (tests and the report; never a path).
abstract final class WipeSteps {
  static const marker = 'marker';
  static const seatKeys = 'seat_keys';
  static const jobs = 'jobs';
  static const closeDb = 'close_db';
  static const keySlots = 'key_slots';
  static const dbFiles = 'db_files';
  static const temp = 'temp';
  static const native = 'native';
  static const signOut = 'sign_out';
}

/// What a run did. [failed] lists the step ids that failed; when it is
/// empty the marker was removed. [remote] completes when the best-effort
/// backend delete ended (true: the server confirmed); the caller never has
/// to wait for it.
final class WipeReport {
  WipeReport({required this.failed, required this.remote});

  final List<String> failed;
  final Future<bool> remote;

  bool get complete => failed.isEmpty;

  @override
  String toString() => 'WipeReport(failed: $failed)';
}

/// Sends `DELETE /v1/installs/me` for [credentials]. Best effort: one retry
/// after a retryable failure or a timeout. True when the server answered
/// with success.
typedef RemoteInstallDelete = Future<bool> Function(InstallCredentials c);

final class DeleteEverything {
  DeleteEverything({
    required this._readInstall,
    required this._deleteRemote,
    required this._rotateSeatKeys,
    required this._cancelJobs,
    required this._closeDatabase,
    required this._secrets,
    required this._files,
    required this._tempDirectory,
    required this._native,
    required this._signOutLocal,
    required this._marker,
    this._leaseTimeout = const Duration(seconds: 35),
  });

  final Future<InstallCredentials?> Function() _readInstall;
  final RemoteInstallDelete _deleteRemote;
  final Future<void> Function() _rotateSeatKeys;
  final Future<void> Function() _cancelJobs;
  final Future<void> Function() _closeDatabase;
  final SecretStore _secrets;
  final DbFileSet _files;
  final Future<Directory> Function() _tempDirectory;
  final NativeWipe _native;
  final Future<void> Function() _signOutLocal;
  final WipeMarker _marker;
  final Duration _leaseTimeout;

  Future<WipeReport>? _running;

  /// The user confirmed: the full wipe, then the backend delete in the
  /// background. Concurrent calls share one run.
  Future<WipeReport> run() =>
      _running ??= _run(remote: true).whenComplete(() => _running = null);

  /// A launch found the marker: the local steps again, no backend call (the
  /// token went with the database).
  Future<WipeReport> resume() =>
      _running ??= _run(remote: false).whenComplete(() => _running = null);

  Future<WipeReport> _run({required bool remote}) async {
    final failed = <String>[];
    Future<void> step(String id, Future<void> Function() body) async {
      try {
        await body();
      } on Object {
        failed.add(id);
      }
    }

    // 1. The marker first: whatever happens next, the next launch resumes.
    await step(WipeSteps.marker, _marker.set);

    // 2. The credentials, read while the database is still open.
    InstallCredentials? creds;
    if (remote) {
      try {
        creds = await _readInstall();
      } on Object {
        creds = null;
      }
    }

    // 3. iOS seat keys: the own key becomes an earlier key (D-55, R4-8).
    //    Not a local-data step: a failure is retried by the next install's
    //    binding check, so it never keeps the marker.
    try {
      await _rotateSeatKeys();
    } on Object {
      // Covered by the install binding (seat_keys.dart).
    }

    // 4–5. Jobs, then the database.
    await step(WipeSteps.jobs, _cancelJobs);
    await step(WipeSteps.closeDb, _closeDatabase);

    // 6. Crypto-shred: the database key and the backup key.
    await step(WipeSteps.keySlots, _deleteKeySlots);

    // 7. The database files (main file last) and the temp directory.
    await step(WipeSteps.dbFiles, _deleteDbFiles);
    await step(
      WipeSteps.temp,
      () => ClearDirectoryStep(WipeSteps.temp, _tempDirectory).run(),
    );

    // 8. Native: jobs, notifications, spool, Guard, Keystore/Keychain
    //    (except the iOS seat keys), sandbox and App Group contents.
    await step(WipeSteps.native, _native.wipeLocalData);

    // 10. The local Google sign-in session (best effort, not local data).
    try {
      await _signOutLocal();
    } on Object {
      // Nothing financial; the Keychain sweep covers iOS.
    }

    if (failed.isEmpty) {
      await step(WipeSteps.marker, _marker.clear);
    } else {
      // The native step clears the app support directory, marker included:
      // put it back so the next launch resumes.
      try {
        await _marker.set();
      } on Object {
        // Nothing more to do; the failure is in the report.
      }
    }

    // 9. The backend, never awaited by the caller.
    final c = creds;
    final Future<bool> remoteDone = c == null
        ? Future<bool>.value(false)
        : _deleteRemote(c).catchError((Object _) => false);
    return WipeReport(failed: List.unmodifiable(failed), remote: remoteDone);
  }

  Future<void> _deleteKeySlots() async {
    final lease = await _secrets.acquireBootstrapLease(_leaseTimeout);
    try {
      for (final slot in SecretSlot.values) {
        await _secrets.delete(lease, slot);
      }
    } finally {
      await _secrets.releaseBootstrapLease(lease);
    }
  }

  Future<void> _deleteDbFiles() async {
    var ok = true;
    for (final s in dbFileWipeSteps(_files)) {
      try {
        await s.run();
      } on FileSystemException {
        ok = false;
      }
    }
    if (!ok || await _files.anyExists()) {
      throw const FileSystemException();
    }
  }
}

// ---- the backend delete ---------------------------------------------------

/// Reads the install credentials from [store] (null before registration).
Future<InstallCredentials?> readInstallCredentials(
  BackendStateStore store,
) async {
  final id = await store.read(BackendStateKeys.installId);
  final token = await store.read(BackendStateKeys.installToken);
  if (id == null || token == null) return null;
  return InstallCredentials(
    installId: utf8.decode(id),
    installToken: utf8.decode(token),
  );
}

/// The production [RemoteInstallDelete]: a throwaway [BackendClient] built
/// by [clientFor] over an in-memory store that holds only [c]. Each attempt
/// is bounded by [timeout]; one retry after a retryable failure or a timeout.
Future<bool> deleteInstallBestEffort(
  InstallCredentials c, {
  required BackendClient Function(BackendStateStore store) clientFor,
  Duration timeout = const Duration(seconds: 10),
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  final client = clientFor(MemoryBackendStateStore.of(c));
  try {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await client.deleteInstall().timeout(timeout);
        return true;
      } on BackendFailure catch (f) {
        if (!f.retryable) return false;
      } on TimeoutException {
        // Retry once.
      }
      if (attempt == 0) await Future<void>.delayed(retryDelay);
    }
    return false;
  } finally {
    await client.dispose();
  }
}

/// A [BackendStateStore] in memory: the backend delete's only state. It is
/// dropped with the client; nothing reaches disk.
final class MemoryBackendStateStore implements BackendStateStore {
  MemoryBackendStateStore();

  factory MemoryBackendStateStore.of(InstallCredentials c) =>
      MemoryBackendStateStore()
        .._values[BackendStateKeys.installId] = Uint8List.fromList(
          utf8.encode(c.installId),
        )
        .._values[BackendStateKeys.installToken] = Uint8List.fromList(
          utf8.encode(c.installToken),
        );

  final Map<String, Uint8List> _values = {};

  @override
  Future<Uint8List?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Uint8List value) async =>
      _values[key] = Uint8List.fromList(value);

  @override
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
  }) async {
    if (!_same(_values[key], expected)) return false;
    _values[key] = Uint8List.fromList(next);
    return true;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<bool> deleteIfEquals(String key, Uint8List expected) async {
    if (!_same(_values[key], expected)) return false;
    _values.remove(key);
    return true;
  }

  static bool _same(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'MemoryBackendStateStore';
}
