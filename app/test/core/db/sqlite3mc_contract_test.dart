// T-007: the encrypted-SQLite contract on the host (CI ubuntu, the PO's
// Windows runner). Runs in app-ci's static job on every push and in
// db-platform.yml's host job.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'sqlite3mc_contract.dart';

void main() {
  registerSqlite3mcContract(env: 'host-${Platform.operatingSystem}');

  test('transactions_fts DDL matches database-schema.md as written', () {
    final doc = File('../docs/03-technical/database-schema.md');
    if (!doc.existsSync()) {
      markTestSkipped('docs/ not available from this working directory');
      return;
    }
    expect(doc.readAsStringSync().contains(transactionsFtsDdl), isTrue);
  });

  // db-platform.yml host job only: writes an encrypted database and its key
  // into $ZAGHLOL_DB_INTEROP_DIR (inside $RUNNER_TEMP) so independent CLIs can
  // check it (Ubuntu sqlite3 must refuse it, sqlcipher must read it).
  final interopDir = Platform.environment['ZAGHLOL_DB_INTEROP_DIR'];
  test(
    'interop: write an encrypted database for the sqlcipher CLI',
    () async {
      final dir = Directory(interopDir!);
      final file = File('${dir.path}/interop.db');
      final key = RawKey(randomHexKey());
      final db = openForeground(file, key);
      await writeSentinels(db, Sentinels.random());
      await statement(
        db,
        'INSERT INTO sentinels (latin, arabic) VALUES (?, ?)',
        ['ZGHL-${randomHexKey().substring(0, 16)}', 'حارس'],
      );
      expect(await sentinelCount(db), 2);
      await db.close();
      final keyFile = File('${dir.path}/interop.key');
      keyFile.writeAsStringSync(key.hex, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', keyFile.path]);
      }
      File('${dir.path}/interop.expected').writeAsStringSync('2\n');
    },
    skip: interopDir == null || interopDir.isEmpty
        ? 'ZAGHLOL_DB_INTEROP_DIR not set (db-platform host job only)'
        : false,
  );
}
