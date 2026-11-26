// T-337: Riverpod wiring for the remote config (plain providers, ADR-001).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database_providers.dart';
import '../db/daos/settings_dao.dart';
import '../flags/flags_providers.dart';
import 'remote_config.dart';
import 'remote_config_service.dart';

final remoteConfigServiceProvider = FutureProvider<RemoteConfigService>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final s = RemoteConfigService(
    dao: SecureStateDao(db),
    clock: ref.watch(flagsClockProvider),
  );
  ref.onDispose(s.dispose);
  await s.load();
  return s;
}, name: 'remoteConfigServiceProvider');

/// Typed config; bundled defaults while loading or on error.
final remoteConfigProvider = StreamProvider<RemoteConfig>((ref) async* {
  final s = await ref.watch(remoteConfigServiceProvider.future);
  yield* s.watch();
}, name: 'remoteConfigProvider');
