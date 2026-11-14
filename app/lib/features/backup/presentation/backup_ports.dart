// T-153: the seams the backup screens (S-66, S-04) read through. Widgets never
// touch the services directly: they read these providers, whose defaults wire
// the T-149..T-152 services, and tests override them with fakes.
//
// Failures are typed kinds, never messages: nothing here carries a path, key,
// file name or passphrase.

import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/settings/settings_keys.dart';
import '../../capture/application/capture_providers.dart'
    show ingestionPauseGateProvider;
import '../../catalog_sync/application/sync_orchestrator.dart'
    show SyncOutcomeKind;
import '../../catalog_sync/application/sync_providers.dart'
    show syncOrchestratorProvider, syncPauseGateProvider;
import '../../../ingestion/ingestion_pause_gate.dart'
    show IngestionBusyException;
import '../../../ingestion/native_drain_hold.dart';
import '../application/backup_snapshot_exception.dart';
import '../application/drive_backup_providers.dart';
import '../application/icloud_backup_providers.dart';
import '../application/schedule.dart';
import '../application/schedule_providers.dart';
import '../application/snapshot_tables.dart';
import '../crypto/backup_cipher.dart';
import '../crypto/backup_crypto_exception.dart';
import '../crypto/backup_crypto_providers.dart';
import '../data/drive_backup_exception.dart';
import '../data/drive_store.dart';
import '../data/icloud_backup_exception.dart';
import '../data/icloud_store.dart';

enum BackupProviderKind { drive, icloud }

/// One backup in a listing. [createdAt], [platform] and the size come from
/// file metadata (file name, Drive properties), not from the authenticated
/// header: they label the entry only (FU-140). `seq` is never shown.
final class BackupEntryView {
  const BackupEntryView({
    required this.createdAt,
    required this.handle,
    this.sizeBytes,
    this.platform,
  });

  final DateTime createdAt;
  final int? sizeBytes;

  /// `android`, `ios` or null (unknown).
  final String? platform;

  /// The service entry this view stands for (opaque to the UI).
  final Object handle;
}

enum RestoreFailureKind {
  network,
  signIn,
  newer,
  corrupted,
  wrongPassphrase,
  other,
}

final class RestoreFailure implements Exception {
  const RestoreFailure(this.kind);
  final RestoreFailureKind kind;
  @override
  String toString() => 'RestoreFailure($kind)';
}

/// Maps any backup-related exception to a [RestoreFailureKind].
RestoreFailureKind restoreFailureKindOf(Object e) {
  if (e is RestoreFailure) return e.kind;
  if (e is BackupCryptoException) {
    return switch (e.reason) {
      BackupCryptoErrorCode.wrongPassphrase =>
        RestoreFailureKind.wrongPassphrase,
      BackupCryptoErrorCode.newerSchema ||
      BackupCryptoErrorCode.newerFormat => RestoreFailureKind.newer,
      BackupCryptoErrorCode.notABackup ||
      BackupCryptoErrorCode.corruptHeader ||
      BackupCryptoErrorCode.corruptData ||
      BackupCryptoErrorCode.unsupportedKdf => RestoreFailureKind.corrupted,
      _ => RestoreFailureKind.other,
    };
  }
  if (e is BackupSnapshotException) {
    return switch (e.reason) {
      BackupSnapshotErrorCode.newerSchema => RestoreFailureKind.newer,
      BackupSnapshotErrorCode.corruptContents => RestoreFailureKind.corrupted,
      _ => RestoreFailureKind.other,
    };
  }
  if (e is DriveBackupException) {
    return switch (e.reason) {
      DriveBackupErrorCode.network ||
      DriveBackupErrorCode.rateLimited ||
      DriveBackupErrorCode.serverError => RestoreFailureKind.network,
      DriveBackupErrorCode.signInRequired ||
      DriveBackupErrorCode.signInCancelled ||
      DriveBackupErrorCode.authorizationDenied ||
      DriveBackupErrorCode.notConfigured => RestoreFailureKind.signIn,
      DriveBackupErrorCode.corruptDownload => RestoreFailureKind.corrupted,
      _ => RestoreFailureKind.other,
    };
  }
  if (e is ICloudBackupException) {
    return switch (e.reason) {
      ICloudBackupErrorCode.timeout => RestoreFailureKind.network,
      ICloudBackupErrorCode.unavailable => RestoreFailureKind.signIn,
      ICloudBackupErrorCode.corruptDownload => RestoreFailureKind.corrupted,
      _ => RestoreFailureKind.other,
    };
  }
  return RestoreFailureKind.other;
}

/// List and restore, per provider.
abstract interface class BackupRestoreGateway {
  /// Our backups, newest first. Throws; map with [restoreFailureKindOf].
  /// [interactive] false: never opens a sign-in or consent screen (a passive
  /// listing on S-66 must not pop the account picker).
  Future<List<BackupEntryView>> list(
    BackupProviderKind kind, {
    bool interactive = true,
  });

  /// Restores [entry]. Returns whether the restored key was stored on this
  /// phone (`false`: the key must be recovered with the passphrase).
  Future<bool> restore(
    BackupProviderKind kind,
    BackupEntryView entry,
    String passphrase,
  );

  /// Re-stores the backup key from [passphrase] (restore with `keyStored`
  /// false, or a key mismatch). Throws; map with [restoreFailureKindOf].
  Future<void> recoverKey(String passphrase);
}

final class ServiceBackupRestoreGateway implements BackupRestoreGateway {
  ServiceBackupRestoreGateway(this._ref);
  final Ref _ref;

  @override
  Future<List<BackupEntryView>> list(
    BackupProviderKind kind, {
    bool interactive = true,
  }) async {
    switch (kind) {
      case BackupProviderKind.drive:
        final items = await _ref
            .read(driveBackupServiceProvider)
            .list(interactive: interactive);
        return [
          for (final e in items)
            BackupEntryView(
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                e.labelCreatedAtMs,
                isUtc: true,
              ),
              sizeBytes: e.sizeBytes,
              platform: e.labelPlatform,
              handle: e,
            ),
        ];
      case BackupProviderKind.icloud:
        final items = await _ref.read(iCloudBackupServiceProvider).list();
        return [
          for (final e in items)
            BackupEntryView(
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                e.labelCreatedAtMs,
                isUtc: true,
              ),
              sizeBytes: e.sizeBytes,
              handle: e,
            ),
        ];
    }
  }

  @override
  Future<bool> restore(
    BackupProviderKind kind,
    BackupEntryView entry,
    String passphrase,
  ) async {
    final outcome = switch (kind) {
      BackupProviderKind.drive =>
        await _ref
            .read(driveBackupServiceProvider)
            .restore(entry.handle as DriveBackupEntry, passphrase),
      BackupProviderKind.icloud =>
        await _ref
            .read(iCloudBackupServiceProvider)
            .restore(entry.handle as ICloudBackupEntry, passphrase),
    };
    return outcome.keyStored;
  }

  @override
  Future<void> recoverKey(String passphrase) async {
    final keys = await _ref
        .read(backupCipherProvider)
        .recoverWithPassphrase(passphrase);
    keys.zeroize();
  }
}

final backupRestoreGatewayProvider = Provider<BackupRestoreGateway>(
  ServiceBackupRestoreGateway.new,
  name: 'backupRestoreGatewayProvider',
);

/// What the app must do once after a restore (FR-BAK-07, FU-139).
final class RestoreDueFlags {
  const RestoreDueFlags({
    this.regrantDue = false,
    this.catalogResyncDue = false,
  });
  final bool regrantDue;
  final bool catalogResyncDue;
}

/// The duties around a restore swap (FU-139): pausing sync and ingestion
/// writes, and the catalog resync.
abstract interface class RestoreSideEffects {
  /// Pauses catalog/entitlement sync and capture writes so no device-table
  /// write is lost between the carry-over read and the swap (FU-139).
  Future<void> pause();
  Future<void> resume();

  /// Runs a catalog sync now. Throws on failure (the flag then stays set).
  Future<void> resyncCatalog();

  /// Reads the due flags from the (re-opened) database.
  Future<RestoreDueFlags> readFlags();

  /// Clears [key] (`restoreRegrantDueKey` / `restoreCatalogResyncDueKey`).
  Future<void> clearFlag(String key);
}

final class DbRestoreSideEffects implements RestoreSideEffects {
  DbRestoreSideEffects(
    this._ref, {
    this.pauseTimeout = const Duration(seconds: 30),
    this.drainPoll = const Duration(milliseconds: 200),
    this.holdRenewEvery = const Duration(minutes: 3),
  });
  final Ref _ref;

  /// How long [pause] waits for an ingestion write, and then for a native
  /// headless drain, before refusing.
  final Duration pauseTimeout;

  /// FU-194: how often [pause] asks whether the headless drain has ended.
  final Duration drainPoll;

  /// FU-194: the native hold expires on its own after [drainHoldTtl] (so a
  /// crash never stops capture for longer); it is renewed this often while
  /// the restore runs.
  final Duration holdRenewEvery;

  static const Duration drainHoldTtl = Duration(minutes: 10);

  Timer? _renew;

  /// Stops catalog sync and ingestion writes and waits for the one running
  /// (WIRE-SVC), then holds the native headless drain and waits for a running
  /// one to end (FU-194). When either does not finish in time this throws
  /// [IngestionBusyException], so the restore does not start (the flow shows
  /// its generic error) and nothing stays paused or held.
  @override
  Future<void> pause() async {
    final sync = _ref.read(syncPauseGateProvider);
    final ingest = _ref.read(ingestionPauseGateProvider);
    final native = _ref.read(nativeDrainHoldProvider);
    var held = false;
    try {
      await sync.pause();
      await ingest.pause(timeout: pauseTimeout);
      final waited = Stopwatch()..start();
      held = true; // a failed hold may still have written part of it
      var active = await native.hold(drainHoldTtl);
      while (active) {
        if (waited.elapsed >= pauseTimeout) {
          throw const IngestionBusyException();
        }
        await Future<void>.delayed(drainPoll);
        active = await native.headlessActive();
      }
      _renew?.cancel();
      _renew = Timer.periodic(holdRenewEvery, (_) {
        unawaited(
          native.hold(drainHoldTtl).then<void>((_) {}, onError: (Object _) {}),
        );
      });
    } on Object {
      if (held) await _release(native);
      sync.resume();
      ingest.resume();
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    await _release(_ref.read(nativeDrainHoldProvider));
    _ref.read(syncPauseGateProvider).resume();
    _ref.read(ingestionPauseGateProvider).resume();
  }

  Future<void> _release(NativeDrainHold native) async {
    _renew?.cancel();
    _renew = null;
    try {
      await native.release();
    } on Object {
      // The hold expires on its own (at most drainHoldTtl).
    }
  }

  /// A forced sync now. The swap is done, so the sync gate reopens first.
  @override
  Future<void> resyncCatalog() async {
    _ref.read(syncPauseGateProvider).resume();
    final o = await _ref.read(syncOrchestratorProvider.future);
    final out = await o.run(force: true);
    if (out.kind != SyncOutcomeKind.applied) {
      throw StateError('CATALOG_RESYNC_FAILED');
    }
  }

  @override
  Future<RestoreDueFlags> readFlags() async {
    final db = await _ref.read(appDatabaseProvider.future);
    final rows = await db
        .customSelect(
          'SELECT key FROM db_meta WHERE key IN (?, ?)',
          variables: [
            Variable.withString(restoreRegrantDueKey),
            Variable.withString(restoreCatalogResyncDueKey),
          ],
        )
        .get();
    final keys = {for (final r in rows) r.read<String>('key')};
    return RestoreDueFlags(
      regrantDue: keys.contains(restoreRegrantDueKey),
      catalogResyncDue: keys.contains(restoreCatalogResyncDueKey),
    );
  }

  @override
  Future<void> clearFlag(String key) async {
    final db = await _ref.read(appDatabaseProvider.future);
    await db.customStatement('DELETE FROM db_meta WHERE key = ?', [key]);
  }
}

final restoreSideEffectsProvider = Provider<RestoreSideEffects>(
  DbRestoreSideEffects.new,
  name: 'restoreSideEffectsProvider',
);

/// What S-66 does.
abstract interface class BackupActions {
  /// True when a backup key exists on this phone. Throws a
  /// [BackupCryptoException] with keyMismatch when the passphrase is needed.
  Future<bool> hasKey();

  /// First backup: creates the key from [passphrase].
  Future<void> createKey(String passphrase);

  /// Checks [current], then re-keys with [next]. Throws wrongPassphrase.
  Future<void> changePassphrase(String current, String next);

  /// Re-stores the key from [passphrase] after a key mismatch.
  Future<void> recoverKey(String passphrase);

  /// Backs up now. Throws a code-only exception (see [backupErrorKindOf]).
  Future<void> backupNow(BackupDestinationPref where);

  /// Sets the schedule (Gold). Returns the mode in force.
  Future<BackupScheduleMode> setSchedule(BackupScheduleMode mode);
}

final class ServiceBackupActions implements BackupActions {
  ServiceBackupActions(this._ref);
  final Ref _ref;

  BackupCipher get _cipher => _ref.read(backupCipherProvider);

  @override
  Future<bool> hasKey() async {
    final keys = await _cipher.loadKeys();
    keys?.zeroize();
    return keys != null;
  }

  @override
  Future<void> createKey(String passphrase) async =>
      (await _cipher.createKey(passphrase)).zeroize();

  @override
  Future<void> changePassphrase(String current, String next) async {
    (await _cipher.recoverWithPassphrase(current)).zeroize();
    (await _cipher.changePassphrase(next)).zeroize();
  }

  @override
  Future<void> recoverKey(String passphrase) async =>
      (await _cipher.recoverWithPassphrase(passphrase)).zeroize();

  @override
  Future<void> backupNow(BackupDestinationPref where) async {
    final s = await _ref.read(backupScheduleServiceProvider.future);
    await s.backupNow(where);
  }

  @override
  Future<BackupScheduleMode> setSchedule(BackupScheduleMode mode) async {
    final s = await _ref.read(backupScheduleServiceProvider.future);
    return s.setSchedule(mode);
  }
}

final backupActionsProvider = Provider<BackupActions>(
  ServiceBackupActions.new,
  name: 'backupActionsProvider',
);

enum BackupErrorKind { network, storage, auth, icloud, needsPassphrase, other }

/// Maps a thrown backup failure (a [BackupRunFailure] carries a code only).
BackupErrorKind backupErrorKindOf(Object e) {
  final code = switch (e) {
    BackupRunFailure(:final code) => code,
    BackupCryptoException(:final code) => code,
    DriveBackupException(:final code) => code,
    ICloudBackupException(:final code) => code,
    _ => '',
  };
  if (code == BackupCryptoErrorCode.keyMismatch.safeCode) {
    return BackupErrorKind.needsPassphrase;
  }
  if (code == DriveBackupErrorCode.network.safeCode ||
      code == DriveBackupErrorCode.rateLimited.safeCode ||
      code == DriveBackupErrorCode.serverError.safeCode ||
      code == ICloudBackupErrorCode.timeout.safeCode) {
    return BackupErrorKind.network;
  }
  if (code == DriveBackupErrorCode.quotaExceeded.safeCode ||
      code == ICloudBackupErrorCode.quotaExceeded.safeCode) {
    return BackupErrorKind.storage;
  }
  if (code == DriveBackupErrorCode.signInRequired.safeCode ||
      code == DriveBackupErrorCode.signInCancelled.safeCode ||
      code == DriveBackupErrorCode.authorizationDenied.safeCode) {
    return BackupErrorKind.auth;
  }
  if (code == ICloudBackupErrorCode.unavailable.safeCode) {
    return BackupErrorKind.icloud;
  }
  return BackupErrorKind.other;
}
