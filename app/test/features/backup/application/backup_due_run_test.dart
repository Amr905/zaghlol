// FU-168e: the periodic job's due mark is read on start and resume, only
// after the entitlement was evaluated; a Gold schedule is never cancelled by
// this path. Synthetic data only.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/backup/application/schedule.dart';
import 'package:zaghlol/features/backup/application/schedule_providers.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

final class _Work implements BackupWorkScheduler {
  final calls = <String>[];
  @override
  Future<void> schedule(BackupScheduleMode mode) async =>
      calls.add('schedule:${mode.name}');
  @override
  Future<void> cancel() async => calls.add('cancel');
}

final class _Dest implements BackupDestination {
  @override
  Future<BackupUploadResult> backupNow(
    BackupKeys keys, {
    required int keep,
    required bool interactive,
  }) => throw StateError('not reached: the key loader returns null');
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late _Work work;
  late int keyLoads;
  late int takeDueCalls;
  late bool due;
  late List<BackupAlertKind> alerts;
  late Completer<void> loaded;
  late ProviderContainer c;
  final now = DateTime.utc(2026, 11, 20, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    settings = SettingsRepository(SettingsDao(db));
    await settings.set(Settings.backupSchedule, BackupScheduleMode.daily);
    await settings.set(Settings.backupDestination, BackupDestinationPref.drive);
    // 40 days old: the schedule is due and the stale reminder is due.
    await settings.set(
      Settings.backupLastSuccess,
      now.subtract(const Duration(days: 40)).millisecondsSinceEpoch,
    );
    work = _Work();
    keyLoads = 0;
    takeDueCalls = 0;
    due = true;
    alerts = [];
    loaded = Completer<void>();
    c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        entitlementLoadedProvider.overrideWithValue(() => loaded.future),
        backupDueTakerProvider.overrideWithValue(() async {
          takeDueCalls++;
          final was = due;
          due = false; // read once, like the native mark
          return was;
        }),
        backupScheduleServiceProvider.overrideWith(
          (ref) async => BackupScheduleService(
            settings: settings,
            entitlement: () => ref.read(entitlementStateProvider),
            destinations: (_) => _Dest(),
            // A run that reaches the key store is a run that started.
            loadKeys: () async {
              keyLoads++;
              return null;
            },
            work: work,
            alert: (kind, {required periodKey}) async => alerts.add(kind),
            now: () => now,
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  void gold() => c
      .read(entitlementStateProvider.notifier)
      .applyVerified(verified: true, status: 'active');

  test('due + Gold runs the backup and the stale reminder', () async {
    gold();
    loaded.complete();
    expect(await c.read(backupDueRunProvider)(), isTrue);
    expect(keyLoads, 1);
    expect(alerts, contains(BackupAlertKind.reminder));
    // Reconcile after the run: the next (iOS one-shot) request is submitted.
    expect(work.calls, ['schedule:daily']);
  });

  test(
    'due + entitlement still loading waits: the mark is not read, nothing '
    'runs, nothing is cancelled; it runs when the entitlement lands',
    () async {
      final run = c.read(backupDueRunProvider)();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(takeDueCalls, 0);
      expect(keyLoads, 0);
      expect(work.calls, isEmpty);
      // The default phase is Free only because nothing was read yet.
      expect(c.read(entitlementStateProvider).isGold, isFalse);

      gold();
      loaded.complete();
      expect(await run, isTrue);
      expect(keyLoads, 1);
      expect(work.calls, ['schedule:daily']);
    },
  );

  test('due + real Free does not run; reconcile cancels the job; the mark '
      'is not read, so a later Gold check still has it', () async {
    loaded.complete(); // evaluated: Free
    expect(await c.read(backupDueRunProvider)(), isFalse);
    expect(keyLoads, 0);
    expect(alerts, isEmpty);
    expect(work.calls, ['cancel']);
    expect(takeDueCalls, 0);
    expect(due, isTrue);

    // Gold arrives later (a restore, a verified token): the mark is used.
    gold();
    expect(await c.read(backupDueRunProvider)(), isTrue);
    expect(keyLoads, 1);
  });

  test('reconcile after verification: not due still re-applies the schedule '
      '(Gold on: schedule; schedule off: cancel)', () async {
    gold();
    loaded.complete();
    due = false;
    await c.read(backupDueRunProvider)();
    expect(work.calls, ['schedule:daily']);
    await settings.set(Settings.backupSchedule, BackupScheduleMode.off);
    await c.read(backupDueRunProvider)();
    expect(work.calls, ['schedule:daily', 'cancel']);
  });

  test(
    'a token still being verified is not Free: nothing is read or run',
    () async {
      c
          .read(entitlementStateProvider.notifier)
          .applyNonGold(EntitlementPhase.pendingVerification);
      loaded.complete();
      expect(await c.read(backupDueRunProvider)(), isFalse);
      expect(takeDueCalls, 0);
      expect(work.calls, isEmpty);
    },
  );

  test('not due: nothing runs', () async {
    gold();
    loaded.complete();
    due = false;
    expect(await c.read(backupDueRunProvider)(), isFalse);
    expect(keyLoads, 0);
    expect(takeDueCalls, 1);
  });

  test('a failing run never throws out of the resume path', () async {
    gold();
    loaded.complete();
    final bad = ProviderContainer(
      overrides: [
        entitlementLoadedProvider.overrideWithValue(() => loaded.future),
        backupDueTakerProvider.overrideWithValue(
          () async => throw StateError('x'),
        ),
      ],
    );
    addTearDown(bad.dispose);
    bad
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    expect(await bad.read(backupDueRunProvider)(), isFalse);
  });

  test('FU-285: a first evaluation that never completes times out, and the '
      'next call is not blocked', () async {
    final never = Completer<void>();
    final slow = ProviderContainer(
      overrides: [
        entitlementLoadedProvider.overrideWithValue(() => never.future),
        backupEntitlementWaitProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
      ],
    );
    addTearDown(slow.dispose);
    final run = slow.read(backupDueRunProvider);
    expect(await run(), isFalse);
    // running was reset: the second call waits again and times out too,
    // instead of returning at once because a run is "in progress".
    final sw = Stopwatch()..start();
    expect(await run(), isFalse);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(4));
  });
}
