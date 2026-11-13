// T-149: Riverpod wiring for the snapshot/restore service. Kept alive: the
// service's in-process lock must be one instance. No provider holds keys.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/db_key_providers.dart';
import '../../../core/db/key_bootstrap.dart';
import '../crypto/backup_crypto_providers.dart';
import 'backup_snapshot_exception.dart';
import 'backup_snapshot_service.dart';

final backupSnapshotServiceProvider = Provider<BackupSnapshotService>((ref) {
  final bootstrap = ref.watch(keyBootstrapProvider);
  return BackupSnapshotService(
    cipher: ref.watch(backupCipherProvider),
    files: ref.watch(dbFileSetProvider),
    tempDirectory: ref.watch(appTempDirectoryProvider),
    liveKey: () async {
      // Read-only: never creates, rotates or wipes (mayCreate false).
      final outcome = await bootstrap.obtain(mayCreate: false);
      switch (outcome) {
        case KeyReady(:final key):
          return key;
        case KeyCreated(:final key, :final lease):
          key.zeroize();
          await lease.release();
        case KeyInvalidated(:final lease):
          // The opener's business (wipe), never the backup's.
          await lease.release();
        case KeyUnavailable() || KeyStoreFailed():
          break;
      }
      throw BackupSnapshotException(BackupSnapshotErrorCode.liveUnavailable);
    },
  );
}, name: 'backupSnapshotServiceProvider');
