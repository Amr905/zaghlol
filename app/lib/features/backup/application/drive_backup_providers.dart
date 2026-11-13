// T-150: Riverpod wiring for the Drive backup host. Kept alive: the store's
// and service's in-process locks must be one instance each. No provider
// holds a token or key.

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../crypto/backup_crypto_providers.dart';
import '../data/drive_auth.dart';
import '../data/drive_store.dart';
import '../data/secure_state_seq_store.dart';
import 'backup_snapshot_providers.dart';
import 'drive_backup_service.dart';

final driveAuthorizerProvider = Provider<DriveAuthorizer>(
  (ref) => GoogleSignInDriveAuthorizer(isIos: Platform.isIOS),
  name: 'driveAuthorizerProvider',
);

final driveConnectorProvider = Provider<DriveConnector>(
  (ref) => GoogleDriveConnector(ref.watch(driveAuthorizerProvider)),
  name: 'driveConnectorProvider',
);

final driveBackupStoreProvider = Provider<DriveBackupStore>(
  (ref) => DriveBackupStore(ref.watch(driveConnectorProvider)),
  name: 'driveBackupStoreProvider',
);

final backupSeqStoreProvider = Provider<BackupSeqStore>(
  (ref) => SecureStateSeqStore(() => ref.read(appDatabaseProvider.future)),
  name: 'backupSeqStoreProvider',
);

final driveBackupServiceProvider = Provider<DriveBackupService>(
  (ref) => DriveBackupService(
    snapshot: ref.watch(backupSnapshotServiceProvider),
    cipher: ref.watch(backupCipherProvider),
    store: ref.watch(driveBackupStoreProvider),
    seq: ref.watch(backupSeqStoreProvider),
    tempDirectory: ref.watch(appTempDirectoryProvider),
  ),
  name: 'driveBackupServiceProvider',
);
