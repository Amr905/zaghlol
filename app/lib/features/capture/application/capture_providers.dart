// T-047: Riverpod composition of the capture module for the UI engine, every
// build (T-041 deviation 3: `startForegroundIngestion({runner})` is replaced;
// the CaptureCoordinator is the CaptureEventsApi handler and drains at start,
// on resume and on `onSpoolChanged`). The coordinator exists only once the
// database gate opened (`appDatabaseProvider`), only on Android until T-066,
// and only when a bundled registry exists; otherwise there is nothing to
// capture with and no retry storm is started (FU-108 security L-2).

import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/foundation.dart' as f show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show ParsingPipeline, Registry;

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/db_key_providers.dart' show dbDirectoryProvider;
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/platform/capture_api.g.dart';
import '../../../core/platform/share_intake_service.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../ingestion/ingest_store.dart';
import '../../../ingestion/ingestion_config.dart';
import '../../../ingestion/ingestion_pause_gate.dart';
import '../../../ingestion/ingestion_runner.dart';
import '../../../ingestion/spike_channel.dart';
import '../../../ingestion/spike_registry.dart' show RegistryGuardBase;
import '../../../ingestion/spool_port.dart';
import '../../../ingestion/ulid.dart';
import '../../ingestion/data/ingest_factory.dart';
import '../../transactions/data/drift_transaction_repository.dart';
import '../data/alert_store.dart';
import '../data/capture_host_port.dart';
import '../data/ios_capture_host_port.dart';
import 'ios_setup_providers.dart';
import '../../ingestion/data/custom_institutions.dart';
import '../data/catch_up_scheduler.dart';
import '../data/guard_inputs_reader.dart';
import '../data/scan_sources.dart';
import '../domain/capture_health.dart';
import 'capture_coordinator.dart';
import 'capture_scheduler.dart';
import 'guard_config_writer.dart';
import 'inbox_scan_service.dart';
import 'scan.dart';

/// The gate the restore flow closes (WIRE-SVC): ingestion writes (drain,
/// inbox scan) stop and the running one is awaited. One per app.
final ingestionPauseGateProvider = Provider<IngestionPauseGate>(
  (ref) => IngestionPauseGate(),
  name: 'ingestionPauseGateProvider',
);

/// The platform's capture host (T-063: the iOS one writes the Guard config
/// the App Intents read; T-066 starts the coordinator on iOS).
final captureHostPortProvider = Provider<CaptureHostPort>(
  (ref) => ref.watch(captureIosProvider)
      ? IosCaptureHostPort()
      : PigeonCaptureHostPort(),
  name: 'captureHostPortProvider',
);

final captureSchedulerProvider = Provider<CaptureScheduler>(
  (ref) => const TimerCaptureScheduler(),
  name: 'captureSchedulerProvider',
);

/// The registry the build parses with (T-036 replaces the missing bundled
/// one). Tests override it.
final captureRegistryLoaderProvider = Provider<Registry Function()>(
  (ref) => defaultRegistryLoader,
  name: 'captureRegistryLoaderProvider',
);

final captureSpoolPortProvider = Provider<SpoolPort>(
  (ref) => platformSpoolPort(),
  name: 'captureSpoolPortProvider',
);

/// Test override of the catch-up port; null (the default) builds the real
/// [InboxScanService] (T-048).
final captureCatchUpProvider = Provider<CatchUpScheduler?>(
  (ref) => null,
  name: 'captureCatchUpProvider',
);

/// The scan service of the running coordinator (first-run scan, re-scan of
/// one institution, progress); null when capture is not running or a test
/// replaced the port.
final inboxScanServiceProvider = FutureProvider<InboxScanService?>((ref) async {
  final c = await ref.watch(captureCoordinatorProvider.future);
  final port = c?.catchUp;
  return port is InboxScanService ? port : null;
}, name: 'inboxScanServiceProvider');

final captureShareIntakeProvider = Provider<ShareIntakeService>((ref) {
  final service = ShareIntakeService();
  ref.onDispose(service.dispose);
  return service;
}, name: 'captureShareIntakeProvider');

/// Android capture (live SMS and notifications). iOS is [captureIosProvider]
/// (T-066): Home's "waiting for SMS" copy stays Android-only.
final captureSupportedProvider = Provider<bool>(
  (ref) => f.defaultTargetPlatform == TargetPlatform.android,
  name: 'captureSupportedProvider',
);

final captureSmsEnabledProvider = settingProvider<bool>(Settings.captureSms);
final captureNotificationsEnabledProvider = settingProvider<bool>(
  Settings.captureNotifications,
);

/// The UI engine's coordinator, started once the database is open. Null when
/// capture cannot run here (not Android, or no registry yet).
final captureCoordinatorProvider = FutureProvider<CaptureCoordinator?>((
  ref,
) async {
  final ios = ref.watch(captureIosProvider);
  if (!ios && !ref.watch(captureSupportedProvider)) return null;
  final Registry registry;
  try {
    registry = ref.watch(captureRegistryLoaderProvider)();
  } on Object {
    return null;
  }
  final db = await ref.watch(appDatabaseProvider.future);
  final host = ref.watch(captureHostPortProvider);
  final scheduler = ref.watch(captureSchedulerProvider);
  final inputs = DriftGuardInputsReader(db);
  final writer = GuardConfigWriter(
    host: host,
    inputs: inputs,
    baseRegistryVersion: registry.registryVersion,
    scheduler: scheduler,
  );
  // One database connection in the UI engine: the runner opens the app's own
  // provider (its `close` is never called here; the container owns the db).
  final container = ref.container;
  final gate = ref.watch(ingestionPauseGateProvider);
  final runner = IngestionRunner(
    marks: defaultCycleMarks(),
    headless: false,
    spool: ref.watch(captureSpoolPortProvider),
    registry: () => registry,
    dbDirectory: () async => ref.read(dbDirectoryProvider),
    store: (_, build) => ProviderIngestStore(
      container,
      build: build,
      gate: gate,
      rebuildPerBatch: true,
    ),
  );
  final share = ref.watch(captureShareIntakeProvider);
  final coordinator = CaptureCoordinator(
    host: host,
    writer: writer,
    alerts: DriftAlertStore(db),
    drain: runner.drain,
    scheduler: scheduler,
    catchUp:
        ref.watch(captureCatchUpProvider) ??
        _buildScanService(ref, db, host, registry, gate),
    hooks: CaptureHooks(
      attachShareIntake: share.attach,
      pollShareIntake: share.pollPending,
      purgeExpired: () =>
          DriftTransactionRepository(TransactionsDao(db)).purgeExpired(),
      foreground: ios
          ? () async {
              // T-062 minor 3: nothing else starts the refresh chain; a
              // submit with the same identifier replaces the pending one.
              await _safeHost(host.scheduleIngestionNow);
              ref.invalidate(iosSetupStatusProvider);
            }
          : null,
    ),
    ios: ios,
    onTablesUpdated: () => markIngestionTablesUpdated(db),
    initialToggles: CaptureToggles(
      sms: ref.read(captureSmsEnabledProvider).value ?? true,
      notifications:
          ref.read(captureNotificationsEnabledProvider).value ?? true,
    ),
  );
  CaptureEventsApi.setUp(coordinator);
  // After a restore the gate reopens: drain what waited in the spool.
  final removeResume = gate.onResume(() => unawaited(coordinator.onResumed()));
  ref.onDispose(removeResume);
  final changes = inputs.changes().listen(
    (_) => coordinator.onGuardInputsChanged(),
  );
  ref.onDispose(() {
    unawaited(changes.cancel());
    CaptureEventsApi.setUp(null);
    unawaited(coordinator.dispose());
  });
  ref.listen(
    captureSmsEnabledProvider,
    (_, _) => _pushToggles(ref, coordinator),
  );
  ref.listen(
    captureNotificationsEnabledProvider,
    (_, _) => _pushToggles(ref, coordinator),
  );
  unawaited(coordinator.start());
  return coordinator;
}, name: 'captureCoordinatorProvider');

Future<void> _safeHost(Future<void> Function() call) async {
  try {
    await call();
  } on Object {
    // Best effort: the foreground drain is the guarantee.
  }
}

InboxScanService _buildScanService(
  Ref ref,
  AppDatabase db,
  CaptureHostPort host,
  Registry registry,
  IngestionPauseGate gate,
) {
  final ids = UlidGenerator();
  final scanner = InboxScanner(
    host: host,
    senders: DriftScanSenderSource(db, () => registry),
    store: ProviderIngestStore(
      ref.container,
      gate: gate,
      rebuildPerBatch: true,
      build: (d) async => buildIngestRawMessages(
        d,
        pipeline: ParsingPipeline(
          await registryWithCustomTemplates(registry, d),
        ),
        guardBase: RegistryGuardBase(registry),
        newId: ids.next,
      ),
    ),
  );
  ref.onDispose(() => unawaited(scanner.dispose()));
  return InboxScanService(
    scanner: scanner,
    host: host,
    alerts: DriftAlertStore(db),
    watermark: DriftWatermarkSource(db),
    enabled: kInboxCatchUpEnabled,
    settings: () async {
      final repo = await ref.read(settingsRepositoryProvider.future);
      return ScanSettings(
        depthMonths: await repo.get(Settings.scanDepthMonths),
        includePersonal: await repo.get(Settings.scanPersonalSenders),
      );
    },
  );
}

void _pushToggles(Ref ref, CaptureCoordinator c) => c.setToggles(
  CaptureToggles(
    sms: ref.read(captureSmsEnabledProvider).value ?? true,
    notifications: ref.read(captureNotificationsEnabledProvider).value ?? true,
  ),
);

/// Headless writes are invisible to this engine's Drift streams (T-046 §10).
void markIngestionTablesUpdated(AppDatabase db) => db.markTablesUpdated([
  db.rawMessages,
  db.transactions,
  db.accounts,
  db.reviewItems,
  db.accountBalances,
]);

/// The app-level capture health (design note §2). The UI maps it to copy.
final captureHealthProvider =
    NotifierProvider<CaptureHealthController, CaptureHealth>(
      CaptureHealthController.new,
      name: 'captureHealthProvider',
    );

class CaptureHealthController extends Notifier<CaptureHealth> {
  @override
  CaptureHealth build() {
    final coordinator = ref.watch(captureCoordinatorProvider).value;
    if (coordinator == null) return CaptureHealth.initial;
    final sub = coordinator.healthChanges.listen((h) => state = h);
    ref.onDispose(sub.cancel);
    return coordinator.health;
  }

  /// Dismisses the missed-notification notice (count only).
  Future<void> dismissMissedNotifications() async =>
      ref.read(captureCoordinatorProvider).value?.dismissMissedNotifications();
}
