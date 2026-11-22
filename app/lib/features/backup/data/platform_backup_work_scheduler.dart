// FU-168e: BackupWorkScheduler over the native periodic wake-up
// (platform-channels.md 4d). Native code only keeps time; when it fires, the
// app reads [takeDue] and runs BackupScheduleService.runScheduled (which
// checks the verified entitlement, schedule and back-off). Nothing here
// carries data.

import '../../../core/platform/backup_work_api.g.dart';
import '../../../core/settings/settings_keys.dart';
import '../application/schedule.dart';

final class PlatformBackupWorkScheduler implements BackupWorkScheduler {
  PlatformBackupWorkScheduler({BackupWorkHostApi? api})
    : _api = api ?? BackupWorkHostApi();

  final BackupWorkHostApi _api;

  /// The wake-up period in days for [mode]; null for off.
  static int? periodDays(BackupScheduleMode mode) => switch (mode) {
    BackupScheduleMode.off => null,
    BackupScheduleMode.daily => 1,
    BackupScheduleMode.weekly => 7,
    BackupScheduleMode.monthly => 30,
  };

  @override
  Future<void> schedule(BackupScheduleMode mode) async {
    final days = periodDays(mode);
    if (days == null) return cancel();
    await _api.schedule(days);
  }

  @override
  Future<void> cancel() => _api.cancel();

  /// True once if the platform job fired since the last call. The caller runs
  /// `runScheduled` and `remindIfStale` when it is true.
  Future<bool> takeDue() => _api.takeDue();
}
