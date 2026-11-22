// T-152: Riverpod wiring for backup schedules. Ports without a platform
// binding yet (the periodic job, the alert text, the iCloud destination, the
// app version) are overridable providers with inert defaults; T-153/T-104 and
// the native job task bind them.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../catalog_sync/application/sync_providers.dart'
    show kClientAppVersion;
import '../../gold/application/entitlement.dart'
    show entitlementServiceProvider;
import '../../gold/application/gating.dart';
import '../crypto/backup_crypto_providers.dart';
import '../crypto/backup_format.dart' show BackupPlatform;
import '../data/platform_backup_work_scheduler.dart';
import 'drive_backup_destination.dart';
import 'drive_backup_providers.dart';
import 'icloud_backup_destination.dart';
import 'icloud_backup_providers.dart';
import 'schedule.dart';

/// Registers the periodic platform job (WorkManager on Android,
/// BGProcessingTask on iOS; FU-168e). Other platforms and tests: does nothing.
final backupWorkSchedulerProvider = Provider<BackupWorkScheduler>(
  (ref) => Platform.isAndroid || Platform.isIOS
      ? PlatformBackupWorkScheduler()
      : const _NoWorkScheduler(),
  name: 'backupWorkSchedulerProvider',
);

/// Reads and clears the native "the periodic job fired" mark (FU-168e).
/// Other platforms and tests: never due.
final backupDueTakerProvider = Provider<Future<bool> Function()>(
  (ref) => Platform.isAndroid || Platform.isIOS
      ? PlatformBackupWorkScheduler().takeDue
      : () async => false,
  name: 'backupDueTakerProvider',
);

/// Completes once the entitlement has been read and evaluated at least once.
/// Until then the in-memory phase is the default Free only because nothing
/// was read, so nothing may act on it (FU-168e). A start that fails leaves
/// this pending; the next resume asks again.
final entitlementLoadedProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(entitlementServiceProvider).firstEvaluation,
  name: 'entitlementLoadedProvider',
);

/// FU-168e: on app start and resume, if the native job fired, runs the
/// scheduled backup and the stale reminder. Waits for the entitlement first
/// (the due mark is read only after it, so it is not lost while waiting), and
/// runs nothing for a verified non-Gold state. After the due mark is handled,
/// and on every call once verified, it calls `reconcile()` (Gold + schedule
/// on: schedule again, which re-submits the one-shot iOS request; Free or
/// off: cancel). One run at
/// a time. Returns whether a due mark was handled. Never throws.
final backupDueRunProvider = Provider<Future<bool> Function()>((ref) {
  var running = false;
  return () async {
    if (running) return false;
    running = true;
    try {
      await ref.read(entitlementLoadedProvider)();
      final entitlement = ref.read(entitlementStateProvider);
      if (entitlement.phase == EntitlementPhase.pendingVerification) {
        return false;
      }
      final service = await ref.read(backupScheduleServiceProvider.future);
      // Verified non-Gold: no run, the mark is left alone; reconcile makes
      // the native schedule match (cancel).
      if (!entitlement.isGold) {
        await service.reconcile();
        return false;
      }
      final handled = await ref.read(backupDueTakerProvider)();
      try {
        if (handled) {
          await service.runScheduled();
          await service.remindIfStale();
        }
      } finally {
        // Every start/resume once verified: the native schedule follows the
        // setting, and an iOS BGProcessingTask (one-shot) is submitted again.
        await service.reconcile();
      }
      return handled;
    } on Object {
      // Code-free by design; the job fires again next period.
      return false;
    } finally {
      running = false;
    }
  };
}, name: 'backupDueRunProvider');

/// Shows the failure and reminder alerts with l10n text through
/// NotificationService. Default: does nothing.
final backupAlertSinkProvider = Provider<BackupAlertSink>(
  (ref) => (kind, {required periodKey}) async {},
  name: 'backupAlertSinkProvider',
);

/// The app version string for backup headers: the build's
/// `ZAGHLOL_APP_VERSION` define (the same value the sync sends).
final backupAppVersionProvider = Provider<String>(
  (ref) => kClientAppVersion,
  name: 'backupAppVersionProvider',
);

/// iCloud (T-151) adapter on iOS; null on Android (no iCloud there).
final icloudBackupDestinationProvider = Provider<BackupDestination?>(
  (ref) => Platform.isIOS
      ? ICloudBackupDestination.over(
          ref.watch(iCloudBackupServiceProvider),
          platform: BackupPlatform.ios,
          appVersion: ref.watch(backupAppVersionProvider),
        )
      : null,
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
