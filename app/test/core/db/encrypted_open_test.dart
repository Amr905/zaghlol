// T-015: the keyed open sequence on the host's sqlite3mc (design note §5, §7;
// T-007 security I-2). Same key reopens; a wrong key is DB_KEY_REJECTED (the
// T-016 hook); failures carry codes only; drift statement logging is off.
//
// Keys are synthetic (support/synthetic_key.dart), never printed.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/backends.dart' show DelegatedDatabase;
import 'package:drift/drift.dart' show QueryExecutor, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';

import '../../support/synthetic_key.dart';
import 'sqlite3mc_contract.dart' show ContractDb, dbFiles, hasPlaintextHeader;

DbKeyMaterial _key([int seed = 61]) =>
    DbKeyMaterial.copyOf(syntheticKeyBytes(seed));

Future<Object?> _failureOf(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } on Object catch (e) {
    return e;
  }
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t015_open_');
    file = File('${dir.path}/zaghlol.db');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<void> writeSentinel(QueryExecutor executor) async {
    final db = ContractDb(executor);
    try {
      await db.customStatement('CREATE TABLE s (v TEXT)');
      await db.customStatement("INSERT INTO s (v) VALUES ('t015')");
    } finally {
      await db.close();
    }
  }

  Future<int> sentinelCount(QueryExecutor executor) async {
    final db = ContractDb(executor);
    try {
      final rows = await db.customSelect('SELECT count(*) AS n FROM s').get();
      return rows.single.data['n'] as int;
    } finally {
      await db.close();
    }
  }

  for (final background in [false, true]) {
    final mode = background ? 'background' : 'foreground';

    test('same key reopens the database ($mode)', () async {
      await writeSentinel(
        openEncryptedExecutor(file, _key(), inBackground: background),
      );
      expect(hasPlaintextHeader(file), isFalse);
      expect(
        await sentinelCount(
          openEncryptedExecutor(file, _key(), inBackground: background),
        ),
        1,
      );
    });

    test('a wrong key is DB_KEY_REJECTED with SQLITE_NOTADB ($mode)', () async {
      await writeSentinel(
        openEncryptedExecutor(file, _key(), inBackground: background),
      );
      final error = await _failureOf(
        () => sentinelCount(
          openEncryptedExecutor(file, _key(62), inBackground: background),
        ),
      );
      expect(error, isNotNull);
      final open = dbOpenExceptionOf(error!);
      expect(open, isNotNull);
      expect(open!.isKeyRejected, isTrue);
      expect(open.sqliteCode, sqliteNotADb);
      // Neither key appears in the error text.
      final text = Uint8List.fromList('$error $open'.codeUnits);
      expect(
        containsAnyNeedle(text, [
          ...keyNeedles(syntheticKeyBytes(61)),
          ...keyNeedles(syntheticKeyBytes(62)),
        ]),
        isFalse,
      );
    });
  }

  test('a plaintext file is refused, never opened as plaintext', () async {
    final plain = ContractDb(NativeDatabase(file));
    await plain.customStatement('CREATE TABLE s (v TEXT)');
    await plain.close();
    final error = await _failureOf(
      () => sentinelCount(
        openEncryptedExecutor(file, _key(), inBackground: false),
      ),
    );
    final open = dbOpenExceptionOf(error!);
    expect(open, isNotNull);
    expect(
      open!.isKeyRejected || open.code == DbOpenException.notEncrypted,
      isTrue,
    );
  });

  test('the database files hold no form of the key', () async {
    final executor = openEncryptedExecutor(file, _key(), inBackground: false);
    final db = ContractDb(executor);
    await db.customStatement('CREATE TABLE s (v TEXT)');
    await db.customStatement('PRAGMA wal_autocheckpoint = 0');
    await db.customStatement("INSERT INTO s (v) VALUES ('t015')");
    final needles = keyNeedles(syntheticKeyBytes());
    for (final f in dbFiles(file)) {
      if (!f.existsSync()) continue;
      expect(containsAnyNeedle(f.readAsBytesSync(), needles), isFalse);
    }
    await db.close();
    for (final f in dbFiles(file)) {
      if (!f.existsSync()) continue;
      expect(containsAnyNeedle(f.readAsBytesSync(), needles), isFalse);
    }
  });

  group('drift statement logging is off (I-2(3))', () {
    late void Function(String) savedPrint;
    late List<String> printed;

    setUp(() {
      savedPrint = driftRuntimeOptions.debugPrint;
      printed = [];
      driftRuntimeOptions.debugPrint = printed.add;
    });

    tearDown(() => driftRuntimeOptions.debugPrint = savedPrint);

    test('the constant and the executor', () async {
      expect(driftLogStatements, isFalse);
      final executor = openEncryptedExecutor(file, _key(), inBackground: false);
      expect((executor as DelegatedDatabase).logStatements, isFalse);
      await writeSentinel(executor);
      expect(printed, isEmpty);
    });

    test(
      'control: a logging executor does print (the capture works)',
      () async {
        final db = ContractDb(NativeDatabase(file, logStatements: true));
        await db.customSelect('SELECT 1').get();
        await db.close();
        expect(printed, isNotEmpty);
      },
    );
  });

  test('dbOpenExceptionOf unwraps only known shapes', () {
    final e = DbOpenException(DbOpenException.openFailed, sqliteCode: 5);
    expect(dbOpenExceptionOf(e), same(e));
    expect(dbOpenExceptionOf('DB_KEY_REJECTED')!.isKeyRejected, isTrue);
    expect(dbOpenExceptionOf('anything else'), isNull);
    expect(dbOpenExceptionOf(StateError('x')), isNull);
    expect(e.toString(), 'DB_OPEN_FAILED');
  });
}
