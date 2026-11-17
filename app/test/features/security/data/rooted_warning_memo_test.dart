// FU-130: the rooted-warning mark over db_meta (in-memory database).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';
import 'package:zaghlol/features/security/data/rooted_warning_memo.dart';

void main() {
  test('unset until marked; marking twice is fine; db_meta is a device '
      'table (not in backups)', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final memo = DbRootedWarningMemo(() async => db);
    expect(await memo.seen(), isFalse);
    await memo.markSeen();
    await memo.markSeen();
    expect(await memo.seen(), isTrue);
    expect(deviceTables, contains('db_meta'));
    expect(backedUpTables, isNot(contains('db_meta')));
  });
}
