// T-008: the database side of a drain cycle. The headless engine opens with
// allowMigration and allowCreateOrWipe false (Q6): it never creates, wipes or
// migrates; those cases come back as DB_DEFERRED / DB_MIGRATION_PENDING and
// the spool is kept for the UI engine.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/db/app_database.dart';
import '../core/db/app_database_opener.dart';
import '../core/db/app_database_providers.dart';
import '../core/db/daos/raw_messages_dao.dart';
import '../core/db/db_key_providers.dart';
import 'raw_message_mapper.dart';

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

  /// Inserts [rows] in one transaction; returns how many were new. Throws on
  /// any failure (nothing committed).
  Future<int> commit(List<StoreRow> rows);

  Future<void> close();
}

/// [IngestStore] over the app's Riverpod database providers.
final class ProviderIngestStore implements IngestStore {
  ProviderIngestStore(this._container);

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
      throw IngestStoreUnavailable(e.failure.code);
    } on Object {
      throw const IngestStoreUnavailable('DB_UNAVAILABLE');
    }
  }

  @override
  Future<int> commit(List<StoreRow> rows) async {
    final db = _db;
    if (db == null) throw const IngestStoreUnavailable('DB_UNAVAILABLE');
    final dao = RawMessagesDao(db);
    return db.transaction(() async {
      var inserted = 0;
      for (final r in rows) {
        if (await dao.insertIfNew(r.row)) inserted++;
      }
      return inserted;
    });
  }

  @override
  Future<void> close() async {
    _db = null;
    _container.dispose();
  }
}
