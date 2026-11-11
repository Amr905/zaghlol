// T-025: Riverpod wiring for the feature flags (ADR-001: plain providers).
// While the database is opening, or if it failed, every flag reads OFF.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database_providers.dart';
import '../db/daos/settings_dao.dart';
import 'feature_flags.dart';
import 'flags_service.dart';

/// The clock for snapshot ages (UTC). Overridden in tests.
final flagsClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
  name: 'flagsClockProvider',
);

/// The backend port. Null until the BackendClient (T-141) overrides it;
/// without it `refresh()` reports unavailable and flags stay as stored.
final remoteFlagsSourceProvider = Provider<RemoteFlagsSource?>(
  (ref) => null,
  name: 'remoteFlagsSourceProvider',
);

/// The service, loaded from `secure_state`. Sync (T-143) calls `apply`.
final flagsServiceProvider = FutureProvider<FlagsService>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final service = FlagsService(
    store: SecureStateFlagStore(SecureStateDao(db)),
    clock: ref.watch(flagsClockProvider),
    remote: ref.watch(remoteFlagsSourceProvider),
  );
  ref.onDispose(service.dispose);
  await service.load();
  return service;
}, name: 'flagsServiceProvider');

/// The evaluated flags, updated on every change (no restart needed).
final featureFlagsProvider = StreamProvider<FeatureFlagsState>((ref) async* {
  final service = await ref.watch(flagsServiceProvider.future);
  yield* service.watch();
}, name: 'featureFlagsProvider');

/// One flag: false while loading, on error, or when not verified fresh.
final featureFlagProvider = Provider.family<bool, FeatureFlag>(
  (ref, flag) => ref.watch(featureFlagsProvider).value?.isOn(flag) ?? false,
  name: 'featureFlagProvider',
);
