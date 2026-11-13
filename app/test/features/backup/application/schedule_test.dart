// T-152: backup schedules, slots and reminders. Policy tests are pure; the
// slot tests run the real Drive service (T-150) on an encrypted database and
// an in-memory Drive. AC1: Free backs up twice -> one file. AC2: Gold keeps
// the newest 5. Synthetic data only.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/backup/application/drive_backup_destination.dart';
import 'package:zaghlol/features/backup/application/drive_backup_service.dart';
import 'package:zaghlol/features/backup/application/schedule.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart';
import 'package:zaghlol/features/backup/data/secure_state_seq_store.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../data/fake_drive.dart';
import 'snapshot_test_support.dart';

int ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;

EntitlementState gold() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(entitlementStateProvider.notifier)
      .applyVerified(verified: true, status: 'active');
  return c.read(entitlementStateProvider);
}

final class FakeWork implements BackupWorkScheduler {
  final List<String> calls = [];
  @override
  Future<void> schedule(BackupScheduleMode mode) async =>
      calls.add('schedule:${mode.name}');
  @override
  Future<void> cancel() async => calls.add('cancel');
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('policy', () {
    final base = DateTime(2026, 3, 10, 9);
    test('off is never due; never backed up is due', () {
      expect(
        isScheduleDue(
          mode: BackupScheduleMode.off,
          lastSuccessMs: null,
          now: base,
        ),
        isFalse,
      );
      expect(
        isScheduleDue(
          mode: BackupScheduleMode.daily,
          lastSuccessMs: null,
          now: base,
        ),
        isTrue,
      );
    });

    test('daily: next local calendar day, not 24 hours', () {
      final last = ms(DateTime(2026, 3, 9, 23, 50));
      expect(
        isScheduleDue(
          mode: BackupScheduleMode.daily,
          lastSuccessMs: last,
          now: DateTime(2026, 3, 10, 0, 5),
        ),
        isTrue,
      );
      expect(
        isScheduleDue(
          mode: BackupScheduleMode.daily,
          lastSuccessMs: ms(DateTime(2026, 3, 10, 0, 1)),
          now: DateTime(2026, 3, 10, 23, 59),
        ),
        isFalse,
      );
    });

    test('weekly: seven calendar days', () {
      final last = ms(DateTime(2026, 3, 3, 20));
      bool due(DateTime n) => isScheduleDue(
        mode: BackupScheduleMode.weekly,
        lastSuccessMs: last,
        now: n,
      );
      expect(due(DateTime(2026, 3, 9, 23)), isFalse);
      expect(due(DateTime(2026, 3, 10, 0, 1)), isTrue);
    });

    test('monthly: same day next month, clamped (31 Jan -> 28/29 Feb)', () {
      bool due(DateTime last, DateTime n) => isScheduleDue(
        mode: BackupScheduleMode.monthly,
        lastSuccessMs: ms(last),
        now: n,
      );
      expect(due(DateTime(2026, 1, 31, 8), DateTime(2026, 2, 27, 9)), isFalse);
      expect(due(DateTime(2026, 1, 31, 8), DateTime(2026, 2, 28, 9)), isTrue);
      expect(due(DateTime(2028, 1, 31, 8), DateTime(2028, 2, 28, 9)), isFalse);
      expect(due(DateTime(2028, 1, 31, 8), DateTime(2028, 2, 29, 9)), isTrue);
      expect(due(DateTime(2026, 12, 15), DateTime(2027, 1, 14)), isFalse);
      expect(due(DateTime(2026, 12, 15), DateTime(2027, 1, 15)), isTrue);
    });

    test('retry backoff is 6 hours after a failure', () {
      final f = ms(DateTime.utc(2026, 3, 10, 6));
      expect(
        inRetryBackoff(lastFailureMs: f, now: DateTime.utc(2026, 3, 10, 11)),
        isTrue,
      );
      expect(
        inRetryBackoff(lastFailureMs: f, now: DateTime.utc(2026, 3, 10, 12)),
        isFalse,
      );
      expect(inRetryBackoff(lastFailureMs: null, now: base), isFalse);
    });

    test('reminder: 30 days, then weekly; none without a backup (A-67)', () {
      final last = ms(DateTime.utc(2026, 1, 1));
      final day30 = DateTime.utc(2026, 1, 31);
      expect(
        isReminderDue(
          lastSuccessMs: last,
          reminderAtMs: null,
          now: DateTime.utc(2026, 1, 30, 23),
        ),
        isFalse,
      );
      expect(
        isReminderDue(lastSuccessMs: last, reminderAtMs: null, now: day30),
        isTrue,
      );
      expect(
        isReminderDue(
          lastSuccessMs: last,
          reminderAtMs: ms(day30),
          now: DateTime.utc(2026, 2, 5),
        ),
        isFalse,
      );
      expect(
        isReminderDue(
          lastSuccessMs: last,
          reminderAtMs: ms(day30),
          now: DateTime.utc(2026, 2, 7),
        ),
        isTrue,
      );
      // A reminder stamped before the last backup does not count.
      expect(
        isReminderDue(
          lastSuccessMs: last,
          reminderAtMs: last - 1000,
          now: day30,
        ),
        isTrue,
      );
      expect(
        isReminderDue(lastSuccessMs: null, reminderAtMs: null, now: day30),
        isFalse,
      );
    });

    test('keep is 1 for Free, 5 for Gold, never below 1', () {
      expect(backupKeepFor(EntitlementState.free), 1);
      expect(backupKeepFor(gold()), 5);
    });
  });

  group('service on a real encrypted DB and an in-memory Drive', () {
    late Phone a;
    late FakeDrive cloud;
    late SettingsRepository settings;
    late FakeWork work;
    late EntitlementState tier;
    late DateTime clock;
    late List<(BackupAlertKind, String)> alerts;
    late BackupScheduleService svc;

    setUp(() async {
      a = await Phone.create(seedA, 't152a');
      await populateSource(a.db);
      (await a.cipher.createKey(passphrase)).zeroize();
      cloud = FakeDrive();
      settings = SettingsRepository(SettingsDao(a.db));
      work = FakeWork();
      tier = EntitlementState.free;
      clock = DateTime.utc(2026, 3, 1, 12);
      alerts = [];
      final drive = DriveBackupDestination(
        DriveBackupService(
          snapshot: a.service(),
          cipher: a.cipher,
          store: DriveBackupStore(FakeConnector(cloud)),
          seq: SecureStateSeqStore(() async => a.db),
          tempDirectory: () async => a.world.tempDir,
        ),
        platform: BackupPlatform.android,
        appVersion: '1.0.0+1',
      );
      svc = BackupScheduleService(
        settings: settings,
        entitlement: () => tier,
        destinations: (w) => w == BackupDestinationPref.drive ? drive : null,
        loadKeys: a.cipher.loadKeys,
        work: work,
        alert: (k, {required periodKey}) async => alerts.add((k, periodKey)),
        now: () => clock,
      );
    });

    tearDown(() => a.dispose());

    int files() => cloud.names.where((n) => n.endsWith('.zaghlol.enc')).length;

    test('AC1: Free backs up twice -> one file', () async {
      await svc.backupNow(BackupDestinationPref.drive);
      clock = clock.add(const Duration(days: 1));
      await svc.backupNow(BackupDestinationPref.drive);
      expect(files(), 1);
      expect(await svc.backupExists(), isTrue);
      expect(await svc.lastBackupAt(), clock);
    });

    test('AC2: Gold keeps the newest 5', () async {
      tier = gold();
      for (var i = 0; i < 7; i++) {
        await svc.backupNow(BackupDestinationPref.drive);
        clock = clock.add(const Duration(days: 1));
      }
      expect(files(), 5);
    });

    test('upgrade keeps the free backup as the first version; downgrade '
        'keeps the newest (FR-BAK-09)', () async {
      await svc.backupNow(BackupDestinationPref.drive); // free
      tier = gold();
      clock = clock.add(const Duration(days: 1));
      await svc.backupNow(BackupDestinationPref.drive);
      expect(files(), 2);
      tier = EntitlementState.free;
      clock = clock.add(const Duration(days: 1));
      await svc.backupNow(BackupDestinationPref.drive);
      expect(files(), 1);
    });

    test('a failed run deletes nothing and leaves the only backup', () async {
      await svc.backupNow(BackupDestinationPref.drive);
      cloud.dropUploadAfter = 100;
      await expectLater(
        svc.backupNow(BackupDestinationPref.drive),
        throwsA(isA<BackupRunFailure>()),
      );
      expect(files(), 1);
      expect(alerts, isEmpty, reason: 'manual runs show the error in the UI');
    });

    test(
      'Free cannot set a schedule: forced off and the job cancelled',
      () async {
        final mode = await svc.setSchedule(BackupScheduleMode.daily);
        expect(mode, BackupScheduleMode.off);
        expect(
          await settings.get(Settings.backupSchedule),
          BackupScheduleMode.off,
        );
        expect(work.calls, ['cancel']);
        final r = await svc.runScheduled();
        expect(r.status, BackupRunStatus.skippedNotGold);
      },
    );

    test('Gold schedule: due run backs up, next call is not due', () async {
      tier = gold();
      expect(
        await svc.setSchedule(BackupScheduleMode.daily),
        BackupScheduleMode.daily,
      );
      expect(work.calls, ['schedule:daily']);
      await settings.set(
        Settings.backupDestination,
        BackupDestinationPref.drive,
      );
      expect((await svc.runScheduled()).status, BackupRunStatus.backedUp);
      expect((await svc.runScheduled()).status, BackupRunStatus.skippedNotDue);
      clock = clock.add(const Duration(days: 1));
      expect((await svc.runScheduled()).status, BackupRunStatus.backedUp);
      expect(files(), 2);
    });

    test(
      'scheduled failure: alert once per day, backoff, success clears',
      () async {
        tier = gold();
        await svc.setSchedule(BackupScheduleMode.daily);
        await settings.set(
          Settings.backupDestination,
          BackupDestinationPref.drive,
        );
        cloud.dropUploadAfter = 100;
        final r = await svc.runScheduled();
        expect(r.status, BackupRunStatus.failed);
        expect(r.code, isNotNull);
        expect(alerts, [(BackupAlertKind.failure, '2026-03-01')]);
        expect(
          (await svc.runScheduled()).status,
          BackupRunStatus.skippedBackoff,
        );
        clock = clock.add(const Duration(hours: 7));
        expect((await svc.runScheduled()).status, BackupRunStatus.backedUp);
        expect(await settings.get(Settings.backupLastFailure), isNull);
      },
    );

    test('lapsed Gold: the scheduled run stops and cancels the job', () async {
      tier = gold();
      await svc.setSchedule(BackupScheduleMode.weekly);
      tier = EntitlementState.free;
      work.calls.clear();
      expect((await svc.runScheduled()).status, BackupRunStatus.skippedNotGold);
      expect(work.calls, ['cancel']);
    });

    test(
      'missing destination or key fails with a code, no alert text',
      () async {
        tier = gold();
        await svc.setSchedule(BackupScheduleMode.daily);
        await settings.set(
          Settings.backupDestination,
          BackupDestinationPref.icloud,
        );
        final r = await svc.runScheduled();
        expect(r.status, BackupRunStatus.failed);
        expect(r.code, 'BACKUP_DESTINATION_UNAVAILABLE');
      },
    );

    test('reminder fires at 30 days, then not again within a week', () async {
      await svc.backupNow(BackupDestinationPref.drive);
      clock = clock.add(const Duration(days: 29));
      expect(await svc.remindIfStale(), isFalse);
      clock = clock.add(const Duration(days: 1));
      expect(await svc.remindIfStale(), isTrue);
      expect(await svc.remindIfStale(), isFalse);
      expect(alerts.single.$1, BackupAlertKind.reminder);
      clock = clock.add(const Duration(days: 7));
      expect(await svc.remindIfStale(), isTrue);
    });

    test(
      'EC-29: delete everything cancels the job and forgets state',
      () async {
        tier = gold();
        await svc.setSchedule(BackupScheduleMode.daily);
        await svc.backupNow(BackupDestinationPref.drive);
        work.calls.clear();
        await svc.cancelAll();
        expect(work.calls, ['cancel']);
        expect(await svc.backupExists(), isFalse);
        expect(
          await settings.get(Settings.backupSchedule),
          BackupScheduleMode.off,
        );
        expect(
          await settings.get(Settings.backupDestination),
          BackupDestinationPref.none,
        );
      },
    );
  });
}
