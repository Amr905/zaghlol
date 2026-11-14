// WIRE-SVC: iCloud (T-151) as a [BackupDestination], the same shape as the
// Drive adapter (T-152).

import '../crypto/backup_format.dart' show BackupPlatform;
import '../crypto/backup_keys.dart';
import 'icloud_backup_service.dart';
import 'schedule.dart';

/// [ICloudBackupService.backupNow] (a function so tests need no service).
typedef ICloudBackupRun = Future<ICloudBackupOutcome> Function(
  BackupKeys keys, {
  required int keep,
  required BackupPlatform platform,
  required String appVersion,
});

final class ICloudBackupDestination implements BackupDestination {
  ICloudBackupDestination(
    this._run, {
    required this.platform,
    required this.appVersion,
  });

  /// Over the real service.
  factory ICloudBackupDestination.over(
    ICloudBackupService service, {
    required BackupPlatform platform,
    required String appVersion,
  }) => ICloudBackupDestination(
    (keys, {required keep, required platform, required appVersion}) =>
        service.backupNow(
          keys,
          keep: keep,
          platform: platform,
          appVersion: appVersion,
        ),
    platform: platform,
    appVersion: appVersion,
  );

  final ICloudBackupRun _run;
  final BackupPlatform platform;
  final String appVersion;

  @override
  Future<BackupUploadResult> backupNow(
    BackupKeys keys, {
    required int keep,
    required bool interactive,
  }) async {
    // iCloud never opens a sign-in screen, so [interactive] has no effect.
    final out = await _run(
      keys,
      keep: keep,
      platform: platform,
      appVersion: appVersion,
    );
    // `uploaded` false: still uploading; the schedule does not count it.
    return BackupUploadResult(confirmed: out.uploaded);
  }
}
