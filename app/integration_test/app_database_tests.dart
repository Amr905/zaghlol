// T-016: AppDatabase on the real Keystore / Keychain and the shipped
// sqlite3mc binaries (design note §9). Registered by db_platform_test.dart, so
// db-platform.yml runs it on the Android API 35 / API 26 emulators and the iOS
// simulator in the same app launch as T-007 and T-015 (a second launch hung
// on CI). Standalone, e.g. on devices:
//   flutter test integration_test/app_database_test.dart --flavor devNoSms -d <id>
//
// AC1: wrong key fails cleanly (DB_KEY_REJECTED, bytes unchanged); the opener
//      turns the rejection into an orphan wipe; a transient failure is
//      DB_UNAVAILABLE and never a wipe.
// AC2: the header of zaghlol.db and of the pre-migration copy is not
//      "SQLite format 3"; WAL/SHM hold no sentinel (with a positive control).
// AC3: a failing migration restores byte-identical files; the old version
//      reopens. D-50: a deleted key wipes every file (main last) and the new
//      database carries the restore notice.
//
// Hygiene: keys are synthetic and never printed; assertions compare
// booleans, counts and codes. Nothing is printed.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/platform/pigeon_secret_store.dart';

import '../test/core/db/db_open_harness.dart';
import '../test/core/db/fake_v2_database.dart';
import '../test/core/db/sqlite3mc_contract.dart'
    show anyFileContains, hasPlaintextHeader;
import '../test/support/file_snapshot.dart';
import '../test/support/synthetic_key.dart';

/// Registers the T-016 device tests. The caller initialises the integration
/// test binding; wrap the call in a `group` to scope setUp/tearDown.
void registerAppDatabaseTests() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final store = PigeonSecretStore();
  late DbWorld world;

  Future<void> resetSlot() async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 35),
    );
    try {
      await store.delete(lease, SecretSlot.dbKey);
    } finally {
      await store.releaseBootstrapLease(lease);
    }
  }

  /// Stores [seed] as the database key (the slot must be empty).
  Future<void> storeKey(int seed) async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 35),
    );
    try {
      await store.createIfAbsent(
        lease,
        SecretSlot.dbKey,
        syntheticKeyBytes(seed),
      );
    } finally {
      await store.releaseBootstrapLease(lease);
    }
  }

  Future<void> firstRun() async {
    final db = openedDb(await world.open(executor: foregroundExecutor));
    await writeMeta(db, 'marker', 'old');
    await db.close();
  }

  setUp(() async {
    await resetSlot();
    world = await DbWorld.create(store, tag: 't016_it');
  });

  tearDown(() async {
    await world.dispose();
    await resetSlot();
  });

  test(
    'renewBootstrapLease: true for the held lease, false after release',
    () async {
      final lease = await store.acquireBootstrapLease(
        const Duration(seconds: 35),
      );
      expect(await store.renewBootstrapLease(lease), isTrue);
      await store.releaseBootstrapLease(lease);
      expect(await store.renewBootstrapLease(lease), isFalse);
    },
  );

  test(
    'AC1: K1 file reopened with K2 → DB_KEY_REJECTED, bytes unchanged',
    () async {
      await firstRun();
      final before = snapshotFiles(world.dbDir);
      final db = AppDatabase(
        openEncryptedExecutor(world.mainFile, keyOf(62)),
        validateSchema: false,
      );
      Object? failure;
      try {
        await db.doWhenOpened((_) {});
      } on Object catch (e) {
        failure = e;
      }
      await db.close();
      expect(dbOpenExceptionOf(failure!)?.isKeyRejected, isTrue);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
    },
  );

  test('AC1: stored key does not open the file → orphan wipe, new key, new '
      'database with the restore notice', () async {
    await firstRun();
    await resetSlot();
    await storeKey(63);
    final result = await world.open(seed: 64);
    final opened = result as DbOpened<AppDatabase>;
    expect(opened.wipedOrphan, isTrue);
    expect(await opened.db.restoreNoticeDue(), isTrue);
    expect(await metaValue(opened.db, 'marker'), isNull);
    await opened.db.close();
    final read = await store.read(SecretSlot.dbKey);
    expect(sameBytes(read.value!, syntheticKeyBytes(64)), isTrue);
    read.value!.fillRange(0, read.value!.length, 0);
  });

  test(
    'AC1: a BUSY/IOERR-style failure is DB_UNAVAILABLE, never a wipe',
    () async {
      await firstRun();
      final before = snapshotFiles(world.dbDir);
      final result = await world.open(
        executor: (file, key, guard) => NativeDatabase(
          file,
          setup: (_) =>
              throw DbOpenException(DbOpenException.openFailed, sqliteCode: 10),
        ),
      );
      expect((result as DbOpenFailed).code, DbOpenFailureCode.unavailable);
      expect(world.wipeLog, isEmpty);
      expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);
      expect((await store.read(SecretSlot.dbKey)).status, SecretStatus.found);
    },
  );

  test('AC2: zaghlol.db header is not "SQLite format 3"; WAL/SHM hold no '
      'sentinel', () async {
    final db = openedDb(await world.open());
    const latin = 'T016DEVICESENTINEL';
    const arabic = 'زغلول_جهاز_تي١٦';
    for (var i = 0; i < 50; i++) {
      await writeMeta(db, 'k$i', '$latin $arabic $i');
    }
    final needles = [utf8.encode(latin), utf8.encode(arabic)];
    final files = [
      world.mainFile,
      File('${world.mainFile.path}-wal'),
      File('${world.mainFile.path}-shm'),
    ];
    expect(hasPlaintextHeader(world.mainFile), isFalse);
    expect(anyFileContains(files, needles), isFalse);
    await db.close();
    final control = File('${world.root.path}/control.bin')
      ..writeAsBytesSync([0, ...needles[0], 0]);
    expect(anyFileContains([control], needles), isTrue);
  });

  test('AC3: a failing v1 → v2 step restores byte-identical files; the copy '
      'was encrypted; v1 reopens', () async {
    await firstRun();
    final before = snapshotFiles(world.dbDir);
    var copyHeaderPlain = true;
    final result = await world.openWith(
      fakeV2Factory(
        mode: FakeV2Mode.throwInStep,
        onStep: () {
          copyHeaderPlain = hasPlaintextHeader(world.files.migrateTmp);
          world.mainFile.writeAsBytesSync(
            List<int>.filled(4096, 0xEE),
            mode: FileMode.append,
            flush: true,
          );
        },
      ),
      FakeV2Database.version,
    );
    final failed = result as DbOpenFailed;
    expect(failed.code, DbOpenFailureCode.migrationFailed);
    expect(failed.restored, isTrue);
    expect(copyHeaderPlain, isFalse);
    for (var i = 0; i < 50; i++) {
      final names = world.dbDir.listSync().map((e) => e.uri.pathSegments.last);
      if (!names.any((n) => n.endsWith('-wal') || n.endsWith('-shm'))) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(sameSnapshot(before, snapshotFiles(world.dbDir)), isTrue);

    final v1 = openedDb(await world.open());
    expect(await userVersionOf(v1), 1);
    expect(await metaValue(v1, 'marker'), 'old');
    await v1.close();
  });

  test('AC3: a successful v1 → v2 migration deletes the copy', () async {
    await firstRun();
    final result = await world.openWith(
      fakeV2Factory(),
      FakeV2Database.version,
    );
    final opened = result as DbOpened<FakeV2Database>;
    expect(opened.migratedFrom, 1);
    expect(await userVersionOf(opened.db), 2);
    expect(world.files.migrateTmp.existsSync(), isFalse);
    await opened.db.close();
  });

  test('D-50: key deleted → every file wiped (main last), new database with '
      'the restore notice', () async {
    await firstRun();
    for (final name in dbWipeOrder) {
      if (name == dbFileName ||
          name == migrateTmpFileName ||
          name == migratePartFileName) {
        continue;
      }
      File('${world.dbDir.path}/$name').writeAsBytesSync(const [7, 7, 7]);
    }
    await resetSlot();
    final result = await world.open(seed: 62);
    final opened = result as DbOpened<AppDatabase>;
    expect(opened.wipedOrphan, isTrue);
    expect(world.wipeLog, [for (final n in dbWipeOrder) 'db:$n', 'temp']);
    expect(await opened.db.restoreNoticeDue(), isTrue);
    await opened.db.close();
  });
}
