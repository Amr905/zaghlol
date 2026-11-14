// T-152: Drive (T-150) as a [BackupDestination]. The iCloud adapter follows
// the same shape once T-151's Dart service lands.

import '../crypto/backup_format.dart' show BackupPlatform;
import '../crypto/backup_keys.dart';
import 'drive_backup_service.dart';
import 'schedule.dart';

final class DriveBackupDestination implements BackupDestination {
  DriveBackupDestination(
    this._service, {
    required this.platform,
    required this.appVersion,
  });

  final DriveBackupService _service;
  final BackupPlatform platform;
  final String appVersion;

  @override
  Future<BackupUploadResult> backupNow(
    BackupKeys keys, {
    required int keep,
    required bool interactive,
  }) async {
    // backupNow returns only after the upload is verified and renamed
    // (T-150); pruning ran after that, or was skipped.
    await _service.backupNow(
      keys,
      keep: keep,
      platform: platform,
      appVersion: appVersion,
      interactive: interactive,
    );
    return const BackupUploadResult(confirmed: true);
  }
}
