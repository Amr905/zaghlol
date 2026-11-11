// T-030: Riverpod wiring for the seed loader. The startup gate watches
// [catalogSeedProvider] after the database is open; a failure there is a
// code-only CatalogSeedException (the app stays usable with an empty
// catalog: categorization falls back to keywords and manual choice).

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

import '../db/app_database_providers.dart';
import 'catalog_seed_loader.dart';

final catalogSeedSourceProvider = Provider<CatalogSeedSource>(
  (ref) => const AssetCatalogSeedSource(),
  name: 'catalogSeedSourceProvider',
);

/// The keys the bundled seed may be signed with. Replaced by the production
/// Sync key before release (see bundledSeedKeys).
final catalogSeedKeysProvider = Provider<List<SeedTrustedKey>>(
  (ref) => bundledSeedKeys(),
  name: 'catalogSeedKeysProvider',
);

/// Loads the bundled seed once (a no-op when the catalog already has a
/// version).
final catalogSeedProvider = FutureProvider<CatalogSeedResult>(
  (ref) async {
    final db = await ref.watch(appDatabaseProvider.future);
    return CatalogSeedLoader(
      db: db,
      source: ref.watch(catalogSeedSourceProvider),
      trustedKeys: ref.watch(catalogSeedKeysProvider),
      // The dev-signed seed loads only outside release builds (S-1).
      allowDevKeys: !kReleaseMode,
    ).loadIfNeeded();
  },
  retry: (retryCount, error) => null,
  name: 'catalogSeedProvider',
);
