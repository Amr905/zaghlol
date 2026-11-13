// T-152 (FR-BAK-02/04/05/08/09, A-25, A-67, EC-29): backup schedules, slots
// and reminders.
//
// Free: one slot, manual only. Gold: a daily/weekly/monthly schedule and the
// newest 5 versions. The count comes from the T-119 gate
// (GoldGate.backupVersionsKept) and is handed to the destination, whose own
// verify-then-prune code (T-150 Drive, T-151 iCloud) is the only thing that
// deletes. Nothing here deletes a backup, and `keep` is never below 1, so a
// schedule can never remove the only good backup (self-check §1).
//
// Upgrade (FR-BAK-09): the free backup is already the oldest of the newest 5,
// so Gold's first run keeps it. Downgrade: the next backup runs with keep 1
// and the destination prunes to the newest, after verifying it.
//
// Nothing here logs; failures are code-only.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../gold/application/gating.dart';
import '../crypto/backup_crypto_exception.dart';
import '../crypto/backup_keys.dart';

/// A-67: a backup older than this earns a reminder.
const Duration backupStaleAfter = Duration(days: 30);

/// How often the reminder may repeat while the backup stays stale.
const Duration backupReminderEvery = Duration(days: 7);

/// After a failed run, the scheduler waits this long before trying again.
const Duration backupRetryBackoff = Duration(hours: 6);

/// What a destination reports after a backup.
final class BackupUploadResult {
  const BackupUploadResult({required this.confirmed});

  /// True when the new backup is verified complete at the destination.
  /// False (iCloud has not finished uploading yet): not counted as a success.
  final bool confirmed;
}

/// One place backups go: Drive (T-150) or iCloud (T-151). The implementation
/// owns verify-then-prune; [keep] is how many newest backups to keep.
abstract interface class BackupDestination {
  Future<BackupUploadResult> backupNow(
    BackupKeys keys, {
    required int keep,
    required bool interactive,
  });
}

/// Loads the stored backup key (BackupCipher.loadKeys); null: no key yet.
typedef BackupKeyLoader = Future<BackupKeys?> Function();

/// Registers or cancels the platform's periodic job (Android WorkManager,
/// iOS BGProcessingTask). The job calls [BackupScheduleService.runScheduled].
abstract interface class BackupWorkScheduler {
  Future<void> schedule(BackupScheduleMode mode);
  Future<void> cancel();
}

enum BackupAlertKind {
  /// FR-NTF-01 "backup failure".
  failure,

  /// A-67: the backup is older than 30 days.
  reminder,
}

/// Shows an alert through NotificationService (T-094). [periodKey] is the
/// dedupe key: one alert per kind and key. The sink supplies l10n text.
typedef BackupAlertSink = Future<void> Function(
  BackupAlertKind kind, {
  required String periodKey,
});

// ---------------------------------------------------------------- policy --

/// Whether a scheduled run is due (local calendar, user's zone): daily, a new
/// local day since the last success; weekly, 7 calendar days; monthly, the
/// same day next month (clamped to the month's length). Never backed up: due.
bool isScheduleDue({
  required BackupScheduleMode mode,
  required int? lastSuccessMs,
  required DateTime now,
}) {
  if (mode == BackupScheduleMode.off) return false;
  if (lastSuccessMs == null) return true;
  final last = DateTime.fromMillisecondsSinceEpoch(
    lastSuccessMs,
    isUtc: true,
  ).toLocal();
  final today = DateTime(
    now.toLocal().year,
    now.toLocal().month,
    now.toLocal().day,
  );
  final due = switch (mode) {
    BackupScheduleMode.daily => DateTime(last.year, last.month, last.day + 1),
    BackupScheduleMode.weekly => DateTime(last.year, last.month, last.day + 7),
    BackupScheduleMode.monthly => _plusOneMonth(last),
    BackupScheduleMode.off => today,
  };
  return !today.isBefore(due);
}

DateTime _plusOneMonth(DateTime d) {
  final lastOfNext = DateTime(d.year, d.month + 2, 0).day;
  final day = d.day > lastOfNext ? lastOfNext : d.day;
  return DateTime(d.year, d.month + 1, day);
}

/// True while a failed run's backoff has not passed.
bool inRetryBackoff({required int? lastFailureMs, required DateTime now}) {
  if (lastFailureMs == null) return false;
  final at = DateTime.fromMillisecondsSinceEpoch(lastFailureMs, isUtc: true);
  return now.toUtc().difference(at) < backupRetryBackoff;
}

/// A-67: remind when the last backup is 30 days old, then at most weekly.
/// No backup yet: no reminder (the onboarding suggestion covers that).
bool isReminderDue({
  required int? lastSuccessMs,
  required int? reminderAtMs,
  required DateTime now,
}) {
  if (lastSuccessMs == null) return false;
  final nowMs = now.toUtc().millisecondsSinceEpoch;
  if (nowMs - lastSuccessMs < backupStaleAfter.inMilliseconds) return false;
  if (reminderAtMs == null || reminderAtMs < lastSuccessMs) return true;
  return nowMs - reminderAtMs >= backupReminderEvery.inMilliseconds;
}

/// FR-BAK-05/08: Free keeps 1, Gold 5 (T-119). Always at least 1.
int backupKeepFor(EntitlementState state) {
  final n = GoldGate.backupVersionsKept(state);
  return n < 1 ? 1 : n;
}

// --------------------------------------------------------------- service --

enum BackupRunStatus {
  /// A verified backup was made.
  backedUp,

  /// The destination took the file but has not confirmed it yet.
  unconfirmed,
  skippedNotGold,
  skippedOff,
  skippedNoDestination,
  skippedNotDue,
  skippedBackoff,

  /// The run failed; see [BackupRunResult.code].
  failed,
}

final class BackupRunResult {
  const BackupRunResult(this.status, {this.code});

  final BackupRunStatus status;

  /// The failure's safe code, never a message.
  final String? code;

  @override
  String toString() => 'BackupRunResult($status, $code)';
}

final class BackupScheduleService {
  BackupScheduleService({
    required this._settings,
    required this._entitlement,
    required this._destinations,
    required this._loadKeys,
    required this._work,
    required this._alert,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SettingsRepository _settings;
  final EntitlementState Function() _entitlement;
  final BackupDestination? Function(BackupDestinationPref) _destinations;
  final BackupKeyLoader _loadKeys;
  final BackupWorkScheduler _work;
  final BackupAlertSink _alert;
  final DateTime Function() _now;

  /// FR-BAK-04: when the last verified backup finished (null: never).
  Future<DateTime?> lastBackupAt() async {
    final ms = await _settings.get(Settings.backupLastSuccess);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// A backup has been made from this phone or restored settings say so.
  /// The seam for T-104's `setupBackupExistsProvider` (FU-144).
  Future<bool> backupExists() async =>
      await _settings.get(Settings.backupLastSuccess) != null;

  /// Sets the schedule. Gold only; Free (and a lapsed Gold) gets
  /// [BackupRunStatus.skippedNotGold] semantics: the schedule is forced off.
  /// Returns the mode now in force.
  Future<BackupScheduleMode> setSchedule(BackupScheduleMode mode) async {
    final allowed = GoldGate.check(
      _entitlement(),
      GoldCapability.autoBackupSchedule,
    ).allowed;
    final effective = allowed ? mode : BackupScheduleMode.off;
    await _settings.set(Settings.backupSchedule, effective);
    if (effective == BackupScheduleMode.off) {
      await _work.cancel();
    } else {
      await _work.schedule(effective);
    }
    return effective;
  }

  /// Re-applies the stored schedule at app start or after a tier change:
  /// a lapsed Gold stops its job; Gold keeps it.
  Future<void> reconcile() async {
    final mode = await _settings.get(Settings.backupSchedule);
    final allowed = GoldGate.check(
      _entitlement(),
      GoldCapability.autoBackupSchedule,
    ).allowed;
    if (mode == BackupScheduleMode.off || !allowed) {
      await _work.cancel();
    } else {
      await _work.schedule(mode);
    }
  }

  /// "Back up now" (Free and Gold). Throws the destination's or key store's
  /// code-only exception; the caller (T-153) maps it to text.
  Future<BackupRunResult> backupNow(BackupDestinationPref where) async {
    if (where == BackupDestinationPref.none) {
      return const BackupRunResult(BackupRunStatus.skippedNoDestination);
    }
    final result = await _run(where, interactive: true, notifyOnFailure: false);
    if (result.status == BackupRunStatus.failed) {
      throw BackupRunFailure(result.code!);
    }
    return result;
  }

  /// The platform job's entry point (never interactive).
  Future<BackupRunResult> runScheduled() async {
    if (!GoldGate.check(
      _entitlement(),
      GoldCapability.autoBackupSchedule,
    ).allowed) {
      await _work.cancel();
      return const BackupRunResult(BackupRunStatus.skippedNotGold);
    }
    final mode = await _settings.get(Settings.backupSchedule);
    if (mode == BackupScheduleMode.off) {
      return const BackupRunResult(BackupRunStatus.skippedOff);
    }
    final where = await _settings.get(Settings.backupDestination);
    if (where == BackupDestinationPref.none) {
      return const BackupRunResult(BackupRunStatus.skippedNoDestination);
    }
    final now = _now();
    if (inRetryBackoff(
      lastFailureMs: await _settings.get(Settings.backupLastFailure),
      now: now,
    )) {
      return const BackupRunResult(BackupRunStatus.skippedBackoff);
    }
    if (!isScheduleDue(
      mode: mode,
      lastSuccessMs: await _settings.get(Settings.backupLastSuccess),
      now: now,
    )) {
      return const BackupRunResult(BackupRunStatus.skippedNotDue);
    }
    return _run(where, interactive: false, notifyOnFailure: true);
  }

  /// A-67: fires the "your backup is old" reminder when due. Call on app
  /// start and from the same job. Returns whether it fired.
  Future<bool> remindIfStale() async {
    final now = _now();
    final last = await _settings.get(Settings.backupLastSuccess);
    final at = await _settings.get(Settings.backupReminderAt);
    if (!isReminderDue(lastSuccessMs: last, reminderAtMs: at, now: now)) {
      return false;
    }
    final nowMs = now.toUtc().millisecondsSinceEpoch;
    // The period key is the week index since the last backup, so a retry in
    // the same week is deduplicated by NotificationService.
    final week = (nowMs - last!) ~/ backupReminderEvery.inMilliseconds;
    await _alert(BackupAlertKind.reminder, periodKey: '$last-$week');
    await _settings.set(Settings.backupReminderAt, nowMs);
    return true;
  }

  /// EC-29 ("delete everything"): stop the platform job and forget the
  /// schedule. Backups already in the user's Drive/iCloud are not touched
  /// here (T-166 says what the user is told about them).
  Future<void> cancelAll() async {
    await _work.cancel();
    await _settings.set(Settings.backupSchedule, BackupScheduleMode.off);
    await _settings.set(Settings.backupDestination, BackupDestinationPref.none);
    await _settings.reset(Settings.backupLastSuccess);
    await _settings.reset(Settings.backupLastFailure);
    await _settings.reset(Settings.backupReminderAt);
  }

  Future<BackupRunResult> _run(
    BackupDestinationPref where, {
    required bool interactive,
    required bool notifyOnFailure,
  }) async {
    final dest = _destinations(where);
    if (dest == null) {
      return _fail('BACKUP_DESTINATION_UNAVAILABLE', notifyOnFailure);
    }
    BackupKeys? keys;
    try {
      keys = await _loadKeys();
      if (keys == null) {
        return await _fail(
          BackupCryptoErrorCode.keyMismatch.safeCode,
          notifyOnFailure,
        );
      }
      final out = await dest.backupNow(
        keys,
        keep: backupKeepFor(_entitlement()),
        interactive: interactive,
      );
      if (!out.confirmed) {
        // Not a failure the user can act on: retry after the backoff.
        await _stampFailure();
        return const BackupRunResult(BackupRunStatus.unconfirmed);
      }
      await _settings.set(Settings.backupDestination, where);
      await _settings.set(
        Settings.backupLastSuccess,
        _now().toUtc().millisecondsSinceEpoch,
      );
      await _settings.reset(Settings.backupLastFailure);
      return const BackupRunResult(BackupRunStatus.backedUp);
    } on SafeException catch (e) {
      return await _fail(e.code, notifyOnFailure);
    } on Object {
      return await _fail('BACKUP_UNKNOWN', notifyOnFailure);
    } finally {
      keys?.zeroize();
    }
  }

  Future<BackupRunResult> _fail(String code, bool notify) async {
    await _stampFailure();
    if (notify) {
      final local = _now().toLocal();
      final day =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
      try {
        await _alert(BackupAlertKind.failure, periodKey: day);
      } on Object {
        // An alert that can't be shown must not hide the failure.
      }
    }
    return BackupRunResult(BackupRunStatus.failed, code: code);
  }

  Future<void> _stampFailure() => _settings.set(
    Settings.backupLastFailure,
    _now().toUtc().millisecondsSinceEpoch,
  );
}

final class BackupRunFailure extends SafeException {
  BackupRunFailure(super.code);
}
