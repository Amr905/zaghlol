// T-016: AppDatabase v1 on the host's sqlite3mc (design note §1, §5, §6, §9).
// AC2 (header), the PRAGMAs read back from a live encrypted database, the
// restore notice row, the schema against the committed dump, the debug
// schema check, and the "no statement logging" guard.
//
// Keys are synthetic (support/synthetic_key.dart), never printed.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import '../../support/fake_secret_store.dart';
import 'db_open_harness.dart';
import 'sqlite3mc_contract.dart'
    show ContractDb, anyFileContains, hasPlaintextHeader;

/// The committed dump of [version] (app/drift_schemas/app_database/).
File dumpFile(int version) =>
    File('drift_schemas/app_database/drift_schema_v$version.json');

/// The exact CREATE statements of a dump.
List<String> dumpSql(int version) {
  final json =
      jsonDecode(dumpFile(version).readAsStringSync()) as Map<String, Object?>;
  final out = <String>[];
  for (final entity in json['fixed_sql']! as List<Object?>) {
    for (final s
        in (entity! as Map<String, Object?>)['sql']! as List<Object?>) {
      final stmt = s! as Map<String, Object?>;
      if (stmt['dialect'] == 'sqlite') out.add(stmt['sql']! as String);
    }
  }
  return out;
}

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore());
  });

  tearDown(() => world.dispose());

  test('schemaVersion (read by drift_dev as a literal) equals '
      'appSchemaVersion', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    expect(db.schemaVersion, appSchemaVersion);
    expect(appSchemaVersion, 4);
  });

  for (final background in [false, true]) {
    final mode = background ? 'background' : 'foreground';

    test('AC2: header is not "SQLite format 3" after create + inserts; '
        'WAL/SHM hold no sentinel ($mode)', () async {
      final db = openedDb(
        await world.open(
          executor: background ? defaultDbExecutor : foregroundExecutor,
        ),
      );
      const latin = 'T016SENTINELLATIN';
      const arabic = 'زغلول_سنتينل_تي١٦';
      for (var i = 0; i < 50; i++) {
        await writeMeta(db, 'k$i', '$latin $arabic $i');
      }
      final needles = [utf8.encode(latin), utf8.encode(arabic)];
      // Scanned while open: the rows are in the WAL.
      final open = [
        world.mainFile,
        File('${world.mainFile.path}-wal'),
        File('${world.mainFile.path}-shm'),
      ];
      expect(File('${world.mainFile.path}-wal').existsSync(), isTrue);
      expect(hasPlaintextHeader(world.mainFile), isFalse);
      expect(anyFileContains(open, needles), isFalse);
      await db.close();
      expect(hasPlaintextHeader(world.mainFile), isFalse);
      expect(anyFileContains(open, needles), isFalse);

      // Positive control: the same scan finds a planted plaintext sentinel.
      final control = File('${world.root.path}/control.bin')
        ..writeAsBytesSync([0, ...needles[1], 0]);
      expect(anyFileContains([control], needles), isTrue);
    });

    test(
      'every PRAGMA reads back from a live encrypted database ($mode)',
      () async {
        final db = openedDb(
          await world.open(
            executor: background ? defaultDbExecutor : foregroundExecutor,
          ),
        );
        addTearDown(db.close);
        Future<Object?> pragma(String name) async =>
            (await db.customSelect('PRAGMA $name').getSingle())
                .data
                .values
                .first;

        expect(await pragma('cipher'), 'sqlcipher');
        expect('${await pragma('legacy')}', '4'); // sqlite3mc answers text
        expect(await pragma('temp_store'), 2);
        expect(await pragma('journal_mode'), 'wal');
        expect(await pragma('synchronous'), 1); // NORMAL
        // FU-094: the wait is a Dart busy handler (applyBusyTimeout), so the
        // PRAGMA reads 0; busy_wait_test.dart proves the 5 s wait.
        expect(await pragma('busy_timeout'), 0);
        expect(await pragma('secure_delete'), 2); // FAST
        expect(await pragma('cache_size'), -8192);
        expect(await pragma('foreign_keys'), 1);
        expect(await pragma('user_version'), appSchemaVersion);
      },
    );
  }

  test('restore notice: written in the create transaction when due, read '
      'and cleared', () async {
    final file = world.mainFile;
    await world.dbDir.create(recursive: true);
    final due = AppDatabase(
      openEncryptedExecutor(file, keyOf(61), inBackground: false),
      restoreNoticeDue: true,
    );
    expect(await due.restoreNoticeDue(), isTrue);
    expect(await metaValue(due, restoreNoticeDueKey), '1');
    await due.clearRestoreNotice();
    await due.clearRestoreNotice(); // idempotent
    expect(await due.restoreNoticeDue(), isFalse);
    await due.close();

    // Reopened with the flag set again: no create, so nothing is written.
    final again = AppDatabase(
      openEncryptedExecutor(file, keyOf(61), inBackground: false),
      restoreNoticeDue: true,
    );
    expect(await again.restoreNoticeDue(), isFalse);
    await again.close();
  });

  test('no restore notice on a plain first run', () async {
    final db = openedDb(await world.open());
    addTearDown(db.close);
    expect(await db.restoreNoticeDue(), isFalse);
  });

  test('the created schema equals the committed dump of the current version '
      '(SchemaVerifier startAt(1).validate equivalent)', () async {
    expect(dumpFile(appSchemaVersion).existsSync(), isTrue);
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final fromDump = ContractDb(NativeDatabase.memory());
    addTearDown(fromDump.close);
    for (final sql in dumpSql(appSchemaVersion)) {
      await fromDump.customStatement(sql);
    }
    final live = await schemaShapeOf(db);
    expect(live, isNotEmpty);
    expect(sameSchemaShape(live, await schemaShapeOf(fromDump)), isTrue);
  });

  test('dumps exist for exactly versions 1..appSchemaVersion', () {
    final names = Directory('drift_schemas/app_database')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toSet();
    expect(names, {
      for (var v = 1; v <= appSchemaVersion; v++) 'drift_schema_v$v.json',
    });
  });

  test('debug schema check: an extra table makes the open fail with '
      'DB_SCHEMA_MISMATCH', () async {
    await world.dbDir.create(recursive: true);
    final plain = rawAppDatabase(world.mainFile);
    await plain.customStatement('CREATE TABLE stray (x INTEGER)');
    await plain.close();

    final checked = AppDatabase(
      openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      validateSchema: true,
    );
    Object? failure;
    try {
      await checked.doWhenOpened((_) {});
    } on Object catch (e) {
      failure = e;
    }
    await checked.close();
    expect(failure, isA<DbMigrationException>());
    expect((failure! as DbMigrationException).code, 'DB_SCHEMA_MISMATCH');
  });

  test('the schema check passes on an unchanged database', () async {
    await world.dbDir.create(recursive: true);
    await rawAppDatabase(world.mainFile).close();
    final checked = AppDatabase(
      openEncryptedExecutor(world.mainFile, keyOf(61), inBackground: false),
      validateSchema: true,
    );
    addTearDown(checked.close);
    await checked.doWhenOpened((_) {});
  });

  test('drift statement logging is off and never switched on in lib/', () {
    expect(driftLogStatements, isFalse);
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (RegExp(r'logStatements:\s*true').hasMatch(f.readAsStringSync())) {
        hits.add(f.path);
      }
    }
    expect(hits, isEmpty);
  });
}
