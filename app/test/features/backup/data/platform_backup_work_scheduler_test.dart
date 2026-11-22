import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/backup_work_api.g.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/backup/data/platform_backup_work_scheduler.dart';

class _FakeHost extends BackupWorkHostApi {
  final calls = <String>[];
  bool due = false;

  @override
  Future<void> schedule(int periodDays) async =>
      calls.add('schedule:$periodDays');

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<bool> takeDue() async {
    final d = due;
    due = false;
    return d;
  }
}

void main() {
  test('modes map to 1, 7 and 30 day periods', () async {
    final host = _FakeHost();
    final s = PlatformBackupWorkScheduler(api: host);
    await s.schedule(BackupScheduleMode.daily);
    await s.schedule(BackupScheduleMode.weekly);
    await s.schedule(BackupScheduleMode.monthly);
    expect(host.calls, ['schedule:1', 'schedule:7', 'schedule:30']);
  });

  test('off cancels instead of scheduling', () async {
    final host = _FakeHost();
    await PlatformBackupWorkScheduler(api: host)
        .schedule(BackupScheduleMode.off);
    expect(host.calls, ['cancel']);
  });

  test('takeDue reports the native mark once', () async {
    final host = _FakeHost()..due = true;
    final s = PlatformBackupWorkScheduler(api: host);
    expect(await s.takeDue(), isTrue);
    expect(await s.takeDue(), isFalse);
  });
}
