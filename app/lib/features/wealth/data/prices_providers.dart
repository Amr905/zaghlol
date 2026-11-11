// T-112: Riverpod wiring for the prices store (ADR-001: plain providers).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import 'prices_repository.dart';

/// The clock for price ages (UTC). Overridden in tests.
final pricesClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
  name: 'pricesClockProvider',
);

/// The backend port. Null until the BackendClient (T-141) overrides it;
/// without it `refresh()` reports unavailable and the stored data stays.
final remotePricesSourceProvider = Provider<RemotePricesSource?>(
  (ref) => null,
  name: 'remotePricesSourceProvider',
);

/// Sync (T-143) calls `apply`; valuation (T-113) and the ≈ view (T-115) read.
final pricesRepositoryProvider = FutureProvider<PricesRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return PricesRepository(
    db: db,
    clock: ref.watch(pricesClockProvider),
    remote: ref.watch(remotePricesSourceProvider),
  );
}, name: 'pricesRepositoryProvider');
