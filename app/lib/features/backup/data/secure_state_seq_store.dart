// T-150 (design note §5): the device's last uploaded backup `seq` in
// `secure_state` `backup.seq.v1` (8-byte big-endian). Device state: the
// snapshot never carries `secure_state`. Nothing here logs.

import 'dart:typed_data';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/settings_dao.dart';

const String backupSeqStateKey = 'backup.seq.v1';

/// The last `seq` this device uploaded.
abstract interface class BackupSeqStore {
  /// Null when unset or unreadable as a counter.
  Future<int?> read();

  Future<void> write(int seq);
}

final class SecureStateSeqStore implements BackupSeqStore {
  SecureStateSeqStore(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<AppDatabase> Function() _db;
  final DateTime Function() _clock;

  @override
  Future<int?> read() async {
    final v = await SecureStateDao(await _db()).read(backupSeqStateKey);
    if (v == null || v.length != 8) return null;
    final n = ByteData.sublistView(v).getUint64(0);
    return n < 0 ? null : n;
  }

  @override
  Future<void> write(int seq) async {
    if (seq < 0) throw ArgumentError('BACKUP_SEQ');
    final b = ByteData(8)..setUint64(0, seq);
    await SecureStateDao(await _db()).write(
      backupSeqStateKey,
      b.buffer.asUint8List(),
      at: _clock().toUtc().millisecondsSinceEpoch,
    );
  }
}
