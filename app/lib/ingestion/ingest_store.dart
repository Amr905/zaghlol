// T-008: the database side of a drain cycle. The headless engine opens with
// allowMigration and allowCreateOrWipe false (Q6): it never creates, wipes or
// migrates; those cases come back as DB_DEFERRED / DB_MIGRATION_PENDING and
// the spool is kept for the UI engine. T-046: a batch goes through
// IngestRawMessages (the spike's raw-row-only commit is gone).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/db/app_database.dart';
import '../core/db/app_database_opener.dart';
import '../core/db/app_database_providers.dart';
import '../core/db/db_key_providers.dart';
import '../features/ingestion/application/ingest_raw_messages.dart';
import '../features/ingestion/domain/ingest_types.dart';

/// Why the store could not be used. [code] is a DbOpenFailureCode code.
final class IngestStoreUnavailable implements Exception {
  const IngestStoreUnavailable(this.code);

  final String code;

  @override
  String toString() => 'IngestStoreUnavailable($code)';
}

abstract interface class IngestStore {
  /// False when the database main file is absent (or its presence can't be
  /// read: treated the same, nothing is touched either way).
  Future<bool> databaseExists();

  /// Opens (once) and returns. Throws [IngestStoreUnavailable].
  Future<void> open();

  /// Ingests [batch] in one write transaction (T-046). Throws
  /// [IngestBatchFailed] when nothing was committed, and
  /// [IngestStoreUnavailable] when the store is not open.
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch);

  Future<void> close();
}

/// [IngestStore] over the app's Riverpod database providers.
final class ProviderIngestStore implements IngestStore {
  /// [build] makes the use case over the opened database (once per open).
  ProviderIngestStore(this._container, {required this.build});

  final IngestRawMessages Function(AppDatabase db) build;
  IngestRawMessages? _ingest;

  /// The headless engine's container: same providers as the UI engine,
  /// migration, create and wipe disabled, database directory from the same
  /// [resolveDbDirectory] the UI uses (FU-065 S-7).
  /// [testOverrides] (a fake key store); Riverpod refuses a second override
  /// of the three headless settings, so they can't be relaxed.
  static ProviderContainer headlessContainer(
    Directory dbDirectory, {
    List<Override> testOverrides = const [],
  }) => ProviderContainer(
    overrides: [
      ...testOverrides,
      allowMigrationProvider.overrideWithValue(false),
      allowCreateOrWipeProvider.overrideWithValue(false),
      dbDirectoryProvider.overrideWithValue(dbDirectory),
    ],
  );

  final ProviderContainer _container;
  AppDatabase? _db;

  @override
  Future<bool> databaseExists() async {
    try {
      return await _container.read(dbFileSetProvider).mainFile.exists();
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> open() async {
    if (_db != null) return;
    try {
      _db = await _container.read(appDatabaseProvider.future);
    } on DbOpenFailure catch (e) {
      _forgetFailedOpen();
      throw IngestStoreUnavailable(e.failure.code);
    } on Object {
      _forgetFailedOpen();
      throw const IngestStoreUnavailable('DB_UNAVAILABLE');
    }
  }

  /// FU-081 F4: a failed open is cached by the provider; without this the
  /// engine's next cycle would get the same error until it is destroyed.
  void _forgetFailedOpen() {
    try {
      _container.invalidate(appDatabaseProvider);
    } on Object {
      // Disposed container: the next cycle builds a new store anyway.
    }
  }

  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) {
    final db = _db;
    if (db == null) throw const IngestStoreUnavailable('DB_UNAVAILABLE');
    return (_ingest ??= build(db)).call(batch);
  }

  /// Closes the database connection (awaited, so its isolate has released
  /// the SQLCipher handle and the WAL lock when this returns), then disposes
  /// the container. The container's own `onDispose(db.close)` runs after
  /// that against an already closed database. A close failure is swallowed
  /// (code-free: nothing to report); the container is disposed either way.
  /// The store can't be opened again; a new cycle builds a new store.
  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    _ingest = null;
    try {
      await db?.close();
    } on Object {
      // Nothing to keep: the engine is about to be destroyed.
    } finally {
      _container.dispose();
    }
  }
}
