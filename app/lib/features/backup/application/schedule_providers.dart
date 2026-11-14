// T-152: Riverpod wiring for backup schedules. Ports without a platform
// binding yet (the periodic job, the alert text, the iCloud destination, the
// app version) are overridable providers with inert defaults; T-153/T-104 and
// the native job task bind them.

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../gold/application/gating.dart';
import '../crypto/backup_crypto_providers.dart';
import '../crypto/backup_format.dart' show BackupPlatform;
import 'drive_backup_destination.dart';
import 'drive_backup_providers.dart';
import 'schedule.dart';

/// Registers the periodic platform job. Default: does nothing until the
/// WorkManager / BGProcessingTask binding exists.
final backupWorkSchedulerProvider = Provider<BackupWorkScheduler>(
  (ref) => const _NoWorkScheduler(),
  name: 'backupWorkSchedulerProvider',
);

/// Shows the failure and reminder alerts with l10n text through
/// NotificationService. Default: does nothing.
final backupAlertSinkProvider = Provider<BackupAlertSink>(
  (ref) => (kind, {required periodKey}) async {},
  name: 'backupAlertSinkProvider',
);

/// The app version string for backup headers.
final backupAppVersionProvider = Provider<String>(
  (ref) => '0.0.0',
  name: 'backupAppVersionProvider',
);

/// iCloud (T-151) adapter; null until its Dart service exists.
final icloudBackupDestinationProvider = Provider<BackupDestination?>(
  (ref) => null,
  name: 'icloudBackupDestinationProvider',
);

final backupScheduleServiceProvider = FutureProvider<BackupScheduleService>((
  ref,
) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final drive = DriveBackupDestination(
    ref.watch(driveBackupServiceProvider),
    platform: Platform.isIOS ? BackupPlatform.ios : BackupPlatform.android,
    appVersion: ref.watch(backupAppVersionProvider),
  );
  final icloud = ref.watch(icloudBackupDestinationProvider);
  final cipher = ref.watch(backupCipherProvider);
  return BackupScheduleService(
    settings: settings,
    entitlement: () => ref.read(entitlementStateProvider),
    destinations: (where) => switch (where) {
      BackupDestinationPref.drive => drive,
      BackupDestinationPref.icloud => icloud,
      BackupDestinationPref.none => null,
    },
    loadKeys: cipher.loadKeys,
    work: ref.watch(backupWorkSchedulerProvider),
    alert: ref.watch(backupAlertSinkProvider),
  );
}, name: 'backupScheduleServiceProvider');

/// FR-BAK-04: when the last verified backup finished.
final lastBackupAtProvider = FutureProvider<DateTime?>((ref) async {
  ref.watch(backupLastSuccessProvider);
  final s = await ref.watch(backupScheduleServiceProvider.future);
  return s.lastBackupAt();
}, name: 'lastBackupAtProvider');

final backupLastSuccessProvider = settingProvider(Settings.backupLastSuccess);

/// The seam for T-104's `setupBackupExistsProvider` (FU-144).
final backupExistsProvider = FutureProvider<bool>((ref) async {
  ref.watch(backupLastSuccessProvider);
  final s = await ref.watch(backupScheduleServiceProvider.future);
  return s.backupExists();
}, name: 'backupExistsProvider');

final class _NoWorkScheduler implements BackupWorkScheduler {
  const _NoWorkScheduler();
  @override
  Future<void> schedule(BackupScheduleMode mode) async {}
  @override
  Future<void> cancel() async {}
}
