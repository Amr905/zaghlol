// T-149 (FU-099 item 2): the T-148 key slot store over `secure_state`
// (`backup.key_slot.v1`). The row is device state: the snapshot never carries
// it (snapshot_tables.dart), and restore writes the restored file's slot into
// the staged database before the swap. Nothing here logs.

import 'dart:typed_data';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../crypto/backup_cipher.dart';

/// The `secure_state` key of the backup key slot (T-148 design note §3).
const String backupKeySlotStateKey = 'backup.key_slot.v1';

final class SecureStateKeySlotStore implements BackupKeySlotStore {
  SecureStateKeySlotStore(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The open database (awaited per call, so a re-open after a restore is
  /// picked up).
  final Future<AppDatabase> Function() _db;
  final DateTime Function() _clock;

  @override
  Future<Uint8List?> read() async =>
      SecureStateDao(await _db()).read(backupKeySlotStateKey);

  @override
  Future<void> write(Uint8List slotCbor) async => SecureStateDao(await _db())
      .write(
        backupKeySlotStateKey,
        slotCbor,
        at: _clock().toUtc().millisecondsSinceEpoch,
      );
}
