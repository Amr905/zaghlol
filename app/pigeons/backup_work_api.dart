// Pigeon contract: the periodic backup wake-up (FU-168e). Contract text:
// platform-channels.md section 4d. Regenerate with app/tool/generate_pigeon.sh.
//
// Native code only keeps time. The job it registers never runs Dart, never
// touches a backup and carries no data: when it fires it leaves a "due" mark
// that the app reads with [takeDue] and then runs BackupScheduleService (which
// checks the verified entitlement, the schedule and the retry back-off).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/backup_work_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/backupwork/BackupWorkApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.backupwork',
      errorClassName: 'BackupWorkApiError',
    ),
    swiftOut: 'ios/Runner/Platform/BackupWorkApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'BackupWorkApiError'),
  ),
)
@HostApi()
abstract class BackupWorkHostApi {
  /// Registers (or replaces) the periodic wake-up, every [periodDays] days
  /// (1, 7 or 30). Android: WorkManager periodic work on an unmetered
  /// network, battery not low, storage not low. iOS: a BGProcessingTask
  /// that needs network. Both are best effort; the system picks the time.
  void schedule(int periodDays);

  /// Cancels the wake-up and clears a pending due mark.
  void cancel();

  /// True once if the job fired since the last call (the mark is cleared).
  bool takeDue();
}
