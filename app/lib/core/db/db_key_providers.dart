// T-015: Riverpod wiring for the key bootstrap (ADR-001; design note §6).
//
// No provider here holds key bytes or an outcome: KeyBootstrap is stateless,
// and only T-016's appDatabaseProvider calls obtain(). Riverpod code
// generation arrives with the first feature that needs it; these are plain
// providers (kept alive, never auto-disposed).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/secret_store.dart';
import '../platform/pigeon_secret_store.dart';
import 'db_file_set.dart';
import 'key_bootstrap.dart';

/// Native Keystore/Keychain store. Overridden with a fake in tests.
final secretStoreProvider = Provider<SecretStore>(
  (ref) => PigeonSecretStore(),
  name: 'secretStoreProvider',
);

/// The directory that holds `zaghlol.db`. T-016 owns the path (the app's
/// private support directory) and overrides this provider at startup.
final dbDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('DB_DIRECTORY_NOT_CONFIGURED'),
  name: 'dbDirectoryProvider',
);

/// The database file set used to tell "first run" from "orphaned key".
final dbFileSetProvider = Provider<DbFileSet>(
  (ref) => DbFileSet(ref.watch(dbDirectoryProvider)),
  name: 'dbFileSetProvider',
);

/// The candidate-key source. Tests override it with a fixed synthetic one.
final keyGeneratorProvider = Provider<KeyGenerator>(
  (ref) => SecureKeyGenerator(),
  name: 'keyGeneratorProvider',
);

/// The key bootstrap. Stateless: it never caches an outcome or a key.
final keyBootstrapProvider = Provider<KeyBootstrap>(
  (ref) => KeyBootstrap(
    store: ref.watch(secretStoreProvider),
    files: ref.watch(dbFileSetProvider),
    generator: ref.watch(keyGeneratorProvider),
  ),
  name: 'keyBootstrapProvider',
);
