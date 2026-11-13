// T-143: wiring of the backend client (FU-115), the entitlement service
// (FU-138) and the daily sync. `syncWiringOverrides` goes into the root
// ProviderScope because `entitlementServiceProvider` is declared by T-144 and
// throws until wired.
//
// The release key sets are EMPTY until T-140 creates the production keys: with
// no key nothing verifies, so a release build drops every signed answer and
// grants no Gold (fail closed). Build-time values come from `--dart-define`.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/backend/response_signature.dart';
import '../../../core/backend/transport.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../categorization/data/categorizer_ports.dart';
import '../../categorization/data/recategorizer.dart';
import '../../categorization/data/rules_providers.dart';
import '../../gold/application/entitlement.dart';
import '../../gold/application/gating.dart';
import '../../gold/application/time_anchor.dart';
import '../../gold/application/trusted_time.dart';
import '../../wealth/data/prices_repository.dart';
import 'sync_adapters.dart';
import 'sync_orchestrator.dart';

/// Production response-signing keys (current + next). Empty until T-140.
final List<ResponseKey> releaseResponseKeys = List.unmodifiable(
  <ResponseKey>[],
);

const String _apiBase = String.fromEnvironment(
  'ZAGHLOL_API_BASE',
  defaultValue: 'https://api.zaghlol.app',
);
const String _appVersion = String.fromEnvironment(
  'ZAGHLOL_APP_VERSION',
  defaultValue: '0.1.0',
);
const String _appBuild = String.fromEnvironment(
  'ZAGHLOL_APP_BUILD',
  defaultValue: '1',
);

/// Platform of this build; tests override it.
final clientPlatformProvider = Provider<ClientPlatform>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? ClientPlatform.ios
      : ClientPlatform.android,
  name: 'clientPlatformProvider',
);

final clientIdentityProvider = Provider<ClientIdentity>(
  (ref) => ClientIdentity(
    platform: ref.watch(clientPlatformProvider),
    appVersion: _appVersion,
    build: _appBuild,
  ),
  name: 'clientIdentityProvider',
);

final backendConfigProvider = Provider<BackendConfig>(
  (ref) => BackendConfig(
    baseUri: Uri.parse(_apiBase),
    verifier: ResponseSignatureVerifier(
      releaseResponseKeys,
      allowDevKeys: !kReleaseMode,
    ),
    allowInsecureLocalhost: !kReleaseMode,
  ),
  name: 'backendConfigProvider',
);

final backendTransportProvider = Provider<BackendTransport>(
  (ref) => IoBackendTransport(),
  name: 'backendTransportProvider',
);

final backendStateStoreProvider = Provider<BackendStateStore>(
  (ref) => DeferredBackendStateStore(() async {
    final db = await ref.read(appDatabaseProvider.future);
    return SecureStateBackendStore(SecureStateDao(db));
  }),
  name: 'backendStateStoreProvider',
);

final backendClientProvider = Provider<BackendClient>((ref) {
  final c = BackendClient(
    config: ref.watch(backendConfigProvider),
    identity: ref.watch(clientIdentityProvider),
    transport: ref.watch(backendTransportProvider),
    store: ref.watch(backendStateStoreProvider),
  );
  ref.onDispose(c.dispose);
  return c;
}, name: 'backendClientProvider');

/// Override for T-144's provider (FU-138).
final Override entitlementServiceOverride = entitlementServiceProvider
    .overrideWith((ref) {
      final store = ref.watch(backendStateStoreProvider);
      final clock = HostClockSource();
      final service = EntitlementService(
        backend: BackendClientEntitlementApi(ref.watch(backendClientProvider)),
        store: store,
        time: TrustedTime(store: store, clock: clock),
        anchor: TimeAnchor(clock: clock),
        keys: ResponseSignatureVerifier(
          releaseEntitlementKeys,
          allowDevKeys: !kReleaseMode,
        ),
        sink: NotifierEntitlementSink(
          ref.read(entitlementStateProvider.notifier),
        ),
      );
      ref.onDispose(service.stop);
      return service;
    });

/// Everything the root `ProviderScope` must override for the sync.
final List<Override> syncWiringOverrides = [entitlementServiceOverride];

final syncOrchestratorProvider = FutureProvider<SyncOrchestrator>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final flags = await ref.watch(flagsServiceProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final rules = await ref.watch(rulesRepositoryProvider.future);
  final clock = ref.watch(flagsClockProvider);
  return SyncOrchestrator(
    db: db,
    backend: BackendClientSyncBackend(ref.watch(backendClientProvider)),
    anchor: EntitlementSyncAnchor(ref.watch(entitlementServiceProvider)),
    store: ref.watch(backendStateStoreProvider),
    flags: flags,
    prices: PricesRepository(db: db, clock: clock),
    settings: settings,
    // A fresh memoizing categorizer per run: the catalog just changed.
    recategorize: () async {
      final c = Categorizer(driftCategorizerPorts(db, rules), memoize: true);
      await Recategorizer(db).run(c, at: clock().millisecondsSinceEpoch);
    },
  );
}, name: 'syncOrchestratorProvider');

/// Data for the About status line (T-146 owns the strings).
final syncStatusProvider = FutureProvider<SyncStatus>((ref) async {
  final o = await ref.watch(syncOrchestratorProvider.future);
  return o.status();
}, name: 'syncStatusProvider');
