// T-151: Riverpod wiring for the iCloud backup host. Kept alive: the
// store's and service's in-process locks must be one instance each. iOS
// only: Android never registers the native host (calls would fail as `io`).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../crypto/backup_crypto_providers.dart';
import '../data/icloud_store.dart';
import 'backup_snapshot_providers.dart';
import 'drive_backup_providers.dart' show backupSeqStoreProvider;
import 'icloud_backup_service.dart';

final iCloudFilesProvider = Provider<ICloudFiles>(
  (ref) => PigeonICloudFiles(),
  name: 'iCloudFilesProvider',
);

final iCloudBackupStoreProvider = Provider<ICloudBackupStore>(
  (ref) => ICloudBackupStore(ref.watch(iCloudFilesProvider)),
  name: 'iCloudBackupStoreProvider',
);

final iCloudBackupServiceProvider = Provider<ICloudBackupService>(
  (ref) => ICloudBackupService(
    snapshot: ref.watch(backupSnapshotServiceProvider),
    cipher: ref.watch(backupCipherProvider),
    store: ref.watch(iCloudBackupStoreProvider),
    seq: ref.watch(backupSeqStoreProvider),
    tempDirectory: ref.watch(appTempDirectoryProvider),
  ),
  name: 'iCloudBackupServiceProvider',
);
