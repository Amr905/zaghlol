// T-162: seams the Settings screens read. Each has a safe default so the
// screens work before the owning service is wired (T-174); the app overrides
// them with the real services. Nothing here touches the database from a
// widget.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backup/application/schedule_providers.dart' as backup;
import '../../catalog_sync/application/sync_providers.dart' as sync;
import '../../catalog_sync/application/sync_providers.dart'
    show kClientAppBuild, kClientAppVersion;

/// App version and build number (About).
class AppInfo {
  const AppInfo({required this.version, required this.build});
  final String version;
  final String build;
}

final appInfoProvider = Provider<AppInfo>(
  (ref) => const AppInfo(version: kClientAppVersion, build: kClientAppBuild),
  name: 'settingsAppInfoProvider',
);

/// When the merchant list and prices were last synced (FR-SYNC-06); null:
/// never.
class SyncStatus {
  const SyncStatus({this.catalogAt, this.pricesAt});
  final DateTime? catalogAt;
  final DateTime? pricesAt;
}

final syncStatusProvider = Provider<SyncStatus>((ref) {
  // The orchestrator records one wall time per successful run (catalog,
  // flags and prices together). Null until the database is open or no run
  // has succeeded.
  final ms = ref.watch(sync.syncStatusProvider).value?.lastOkWallMs;
  if (ms == null) return const SyncStatus();
  final at = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return SyncStatus(catalogAt: at, pricesAt: at);
}, name: 'settingsSyncStatusProvider');

/// The install ID shown as the support code; null while not registered.
final supportCodeProvider = FutureProvider<String?>(
  (ref) async => null,
  name: 'settingsSupportCodeProvider',
);

/// The diagnostics text for the share sheet (`DiagExporter.exportText`).
/// Null: no exporter wired, so the row is hidden.
final diagnosticsTextProvider = Provider<Future<String> Function()?>(
  (ref) => null,
  name: 'settingsDiagnosticsTextProvider',
);

/// Hands the diagnostics text to the system share sheet.
final shareTextProvider = Provider<Future<void> Function(String)?>(
  (ref) => null,
  name: 'settingsShareTextProvider',
);

/// Opens a mail draft to support (subject from l10n).
final contactSupportProvider = Provider<Future<void> Function(String subject)?>(
  (ref) => null,
  name: 'settingsContactSupportProvider',
);

/// Wipes the database, keys and files (FR-SEC delete everything).
final wipeEverythingProvider = Provider<Future<void> Function()?>(
  (ref) => null,
  name: 'settingsWipeEverythingProvider',
);

/// The last backup time for the delete dialog; null: none.
final lastBackupAtProvider = Provider<DateTime?>(
  (ref) => ref.watch(backup.lastBackupAtProvider).value,
  name: 'settingsLastBackupAtProvider',
);

/// FR-SEC-07: the phone is rooted or jailbroken.
final deviceCompromisedProvider = Provider<bool>(
  (ref) => false,
  name: 'settingsDeviceCompromisedProvider',
);

/// The Gold plan slug (`monthly`, `yearly`, `lifetime`); null: Free.
final goldPlanProvider = Provider<String?>(
  (ref) => null,
  name: 'settingsGoldPlanProvider',
);

/// Setup steps still skipped (FR-ONB-11).
final setupStepsLeftProvider = Provider<int>(
  (ref) => 0,
  name: 'settingsSetupStepsLeftProvider',
);

/// Subtitle states for the rows that show live status.
final captureStateProvider = Provider<String>(
  (ref) => 'ok',
  name: 'settingsCaptureStateProvider',
);
