// T-149: backup snapshot → encrypted file → restore swap, on real encrypted
// databases (sqlite3mc) for two phones with different K_db.
//
// AC1 checklist: every FR-BAK-06 table identical after restore, device
// tables (FR-BAK-07) kept from the target. AC2: no plaintext file at any
// step (privacy scan of the work dir, DB dir and temp dir). Safety: nothing
// touches live data before the swap; the swap is one transaction.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;
import 'package:zaghlol/features/backup/application/backup_contents.dart';
import 'package:zaghlol/features/backup/application/backup_snapshot_exception.dart';
import 'package:zaghlol/features/backup/application/backup_snapshot_service.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';

import '../../../core/db/db_open_harness.dart';
import '../../../core/db/schema_v3_database.dart';
import 'snapshot_test_support.dart';

Matcher snapCode(BackupSnapshotErrorCode c) => throwsA(
  isA<BackupSnapshotException>().having((e) => e.reason, 'reason', c),
);

Matcher cryptoCode(BackupCryptoErrorCode c) =>
    throwsA(isA<BackupCryptoException>().having((e) => e.reason, 'reason', c));

Stream<List<int>> bytesStream(Uint8List b) async* {
  for (var i = 0; i < b.length; i += 50000) {
    yield b.sublist(i, i + 50000 > b.length ? b.length : i + 50000);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Phone a;
  late Phone b;
  late BackupKeys keysA;

  setUp(() async {
    a = await Phone.create(seedA, 't149a');
    b = await Phone.create(seedB, 't149b');
    await populateSource(a.db);
    await populateTarget(b.db);
    keysA = await a.cipher.createKey(passphrase);
  });

  tearDown(() async {
    keysA.zeroize();
    await a.dispose();
    await b.dispose();
  });

  Future<Uint8List> backupOfA({
    BackupIsolateRunner runner = inlineRunner,
    void Function(String)? onStep,
  }) => collectBytes(
    a
        .service(runner: runner, onStep: onStep)
        .write(
          keysA,
          seq: 3,
          platform: BackupPlatform.android,
          appVersion: '1.0.0+1',
          chunkSize: minChunkSize,
        ),
  );

  test('AC1 checklist: every FR-BAK-06 table identical on the other phone, '
      'device tables kept, restored key stored (background isolate)', () async {
    final source = await dump(a.db, backedUpTables);
    for (final t in backedUpTables) {
      expect(source[t], isNotEmpty, reason: '$t must be populated');
    }
    final bDevice = await dump(b.db, deviceTables);

    final file = await backupOfA(runner: isolateRunner);
    final outcome = await b
        .service(runner: isolateRunner)
        .restore(bytesStream(file), passphrase);

    expect(outcome.schemaVersion, appSchemaVersion);
    expect(outcome.seq, 3);
    expect(outcome.platform, BackupPlatform.android);
    expect(outcome.keyStored, isTrue);

    // Every FR-BAK-06 item (D-19), row for row.
    expect(await dump(b.db, backedUpTables), source);
    // Search works on the restored data (FTS pages travelled with it).
    final hits = await b.db
        .customSelect(
          'SELECT rowid FROM transactions_fts WHERE transactions_fts '
          "MATCH '${noteSentinel.toLowerCase()}'",
        )
        .get();
    expect(hits, hasLength(1));

    // FR-BAK-07: B's device state survives, A's never arrives.
    final after = await dump(b.db, deviceTables);
    for (final t in [
      'outbox',
      'diag_log',
      'catalog_merchants',
      'catalog_meta',
      'catalog_aliases',
      'catalog_keywords',
    ]) {
      expect(after[t], bDevice[t], reason: t);
    }
    final secure = await b.db
        .customSelect('SELECT key, value FROM secure_state')
        .get();
    expect(
      String.fromCharCodes(
        secure
            .firstWhere((r) => r.read<String>('key') == 'install_id')
            .read<Uint8List>('value'),
      ),
      deviceBSentinel,
    );
    expect((await fullDump(b.db)).toString(), isNot(contains(deviceASentinel)));
    // Restore follow-ups (FR-BAK-07 re-grant prompt, catalog re-sync).
    expect(await metaValue(b.db, restoreRegrantDueKey), '1');
    expect(await metaValue(b.db, restoreCatalogResyncDueKey), '1');
    expect(await metaValue(b.db, 'device'), deviceBSentinel);

    // Automatic backups continue on B with A's key, without a passphrase.
    final loaded = await b.cipher.loadKeys();
    expect(loaded, isNotNull);
    expect(loaded!.slot.sameAs(keysA.slot), isTrue);
    loaded.zeroize();

    // The restored DB opens through the app's opener with B's key.
    final reopened = openedDb(await b.world.open(seed: seedB));
    expect(await dump(reopened, backedUpTables), source);
    await reopened.close();
    expect(b.workDir.existsSync(), isFalse);
  });

  test('AC2 privacy: no plaintext file at any step of backup and restore; '
      'the snapshot holds no device secret even in free pages', () async {
    final roots = [a.world.root, b.world.root];
    final seen = <String>[];
    void scan(String step) {
      seen.add(step);
      expect(plaintextLeaks(roots), isEmpty, reason: 'after $step');
    }

    File? snapCopy;
    final file = await collectBytes(
      a
          .service(
            onStep: (s) {
              scan(s);
              if (s == 'snapshot') {
                snapCopy = File('${a.world.root.path}/snapcopy.db')
                  ..writeAsBytesSync(
                    File('${a.workDir.path}/snap.db').readAsBytesSync(),
                  );
              }
            },
          )
          .write(
            keysA,
            seq: 1,
            platform: BackupPlatform.ios,
            appVersion: '1.0.0',
            chunkSize: minChunkSize,
          )
          .map((chunk) {
            scan('stream');
            return chunk;
          }),
    );
    for (final n in leakNeedles) {
      expect(containsBytes(file, n), isFalse);
    }
    await b.service(onStep: scan).restore(bytesStream(file), passphrase);
    scan('done');
    expect(
      seen,
      containsAll([
        'snapshot',
        'stream',
        'encrypted',
        'unlocked',
        'decrypted',
        'staged',
        'carried',
        'swapped',
        'keyStored',
      ]),
    );

    // Decrypt the snapshot copy to plaintext (test only) and search every
    // page, free ones included: device rows were emptied with secure_delete
    // and VACUUM, so they are gone; backed-up rows are there (control).
    final header = BackupHeader.decode(
      file.sublist(
        backupPrefixLength,
        backupPrefixLength + (file[5] << 8 | file[6]),
      ),
    );
    final s = await keysA.snapshotKey(header.fileId);
    final raw = openRaw(snapCopy!, DbKeyMaterial.copyOf(s.bytes));
    s.zeroize();
    raw.execute('PRAGMA journal_mode = DELETE');
    raw.execute("PRAGMA rekey = ''");
    raw.close();
    final plain = snapCopy!.readAsBytesSync();
    expect(containsBytes(plain, sqlitePlaintextMagic), isTrue);
    expect(containsBytes(plain, noteSentinel.codeUnits), isTrue);
    expect(containsBytes(plain, deviceASentinel.codeUnits), isFalse);
    snapCopy!.deleteSync();
  });

  test('older snapshot (schema v3) is migrated on restore', () async {
    final file = await craftBackup(
      a,
      keysA,
      headerSchema: 3,
      prepareSnapshot: (snap, kSnap) async {
        final v3 = File('${snap.parent.path}/v3.db');
        await makeV3File(v3, seed: 99);
        final src = openRaw(v3, keyOf(99));
        final dst = openRaw(snap, kSnap);
        dst.execute('PRAGMA journal_mode = DELETE');
        await src.backup(dst, nPage: -1).drain<void>();
        src.close();
        for (final t in deviceTables.reversed) {
          final exists = dst.select(
            'SELECT 1 FROM sqlite_schema WHERE name = ?',
            [t],
          );
          if (exists.isNotEmpty) dst.execute('DELETE FROM "$t"');
        }
        dst.close();
      },
    );
    final v3Txns = await _countIn(
      keyOf(99),
      (dir) => makeV3File(File('${dir.path}/x.db'), seed: 99),
      'transactions',
    );
    final outcome = await b.service().restore(bytesStream(file), passphrase);
    expect(outcome.schemaVersion, 3);
    expect(await userVersionOf(b.db), appSchemaVersion);
    final n = await b.db
        .customSelect('SELECT count(*) AS n FROM transactions')
        .getSingle();
    expect(n.read<int>('n'), v3Txns);
    expect(v3Txns, greaterThan(0));
  });

  group('refusals leave the live database untouched', () {
    late Map<String, List<String>> before;
    setUp(() async => before = await fullDump(b.db));

    Future<void> expectUntouched() async {
      expect(await fullDump(b.db), before);
      expect(b.workDir.existsSync(), isFalse);
    }

    test(
      'EC-26: a header from a newer schema is refused before the KDF',
      () async {
        final file = await craftBackup(
          a,
          keysA,
          headerSchema: appSchemaVersion + 1,
          mutate: (db) =>
              db.execute('PRAGMA user_version = ${appSchemaVersion + 1}'),
        );
        final kdfBefore = b.kdf.calls;
        await expectLater(
          b.service().restore(bytesStream(file), passphrase),
          cryptoCode(BackupCryptoErrorCode.newerSchema),
        );
        expect(b.kdf.calls, kdfBefore);
        await expectUntouched();
      },
    );

    test('EC-26: a snapshot from a newer schema under an older header is '
        'refused as newerSchema', () async {
      final file = await craftBackup(
        a,
        keysA,
        mutate: (db) =>
            db.execute('PRAGMA user_version = ${appSchemaVersion + 1}'),
      );
      await expectLater(
        b.service().restore(bytesStream(file), passphrase),
        snapCode(BackupSnapshotErrorCode.newerSchema),
      );
      await expectUntouched();
    });

    test('wrong passphrase', () async {
      final file = await backupOfA();
      await expectLater(
        b.service().restore(bytesStream(file), 'not the passphrase'),
        cryptoCode(BackupCryptoErrorCode.wrongPassphrase),
      );
      await expectUntouched();
    });

    test('a truncated file fails as corruptData, nothing staged', () async {
      final file = await backupOfA();
      await expectLater(
        b.service().restore(
          bytesStream(file.sublist(0, file.length - 100)),
          passphrase,
        ),
        cryptoCode(BackupCryptoErrorCode.corruptData),
      );
      await expectUntouched();
    });

    final hostile = <String, Future<Uint8List> Function(Phone, BackupKeys)>{
      'a plaintext SQLite snapshot': (a, k) => craftBackup(
        a,
        k,
        rawSnapshot: (bytes) {
          final copy = Uint8List.fromList(bytes);
          copy.setRange(0, 16, sqlitePlaintextMagic);
          return copy;
        },
      ),
      'a manifest row count that does not match': (a, k) => craftBackup(
        a,
        k,
        editManifest: (m) => SnapshotManifest(
          contentsVersion: m.contentsVersion,
          schemaVersion: m.schemaVersion,
          snapshotBytes: m.snapshotBytes,
          settingsBytes: m.settingsBytes,
          tables: {...m.tables, 'transactions': 99},
        ),
      ),
      'a snapshot carrying device secrets': (a, k) => craftBackup(
        a,
        k,
        mutate: (db) => db.execute(
          'INSERT INTO secure_state (key, value, updated_at) '
          "VALUES ('entitlement_token', x'01', 1)",
        ),
      ),
      'a row breaking a CHECK (integrity_check)': (a, k) => craftBackup(
        a,
        k,
        mutate: (db) {
          db.execute('PRAGMA ignore_check_constraints = ON');
          db.execute('UPDATE voice_usage SET "count" = -1');
        },
      ),
      'a dangling foreign key': (a, k) => craftBackup(
        a,
        k,
        mutate: (db) => db.execute(
          "UPDATE transactions SET account_id = 'nope' WHERE id = 'e1'",
        ),
      ),
      'a foreign trigger (schema shape)': (a, k) => craftBackup(
        a,
        k,
        mutate: (db) => db.execute(
          'CREATE TRIGGER evil AFTER INSERT ON settings BEGIN '
          'DELETE FROM transactions; END',
        ),
      ),
      'a header schema that differs from the snapshot': (a, k) =>
          craftBackup(a, k, headerSchema: 3),
    };
    for (final MapEntry(:key, :value) in hostile.entries) {
      test('$key → corruptContents', () async {
        final file = await value(a, keysA);
        await expectLater(
          b.service().restore(bytesStream(file), passphrase),
          snapCode(BackupSnapshotErrorCode.corruptContents),
        );
        await expectUntouched();
      });
    }
  });

  group('failure or process death at each step', () {
    for (final step in ['unlocked', 'decrypted', 'staged', 'carried']) {
      test('before the swap ($step): live data unchanged', () async {
        final before = await fullDump(b.db);
        final file = await backupOfA();
        await expectLater(
          b
              .service(
                onStep: (s) {
                  if (s == step) throw StateError('crash');
                },
              )
              .restore(bytesStream(file), passphrase),
          throwsStateError,
        );
        expect(await fullDump(b.db), before);
        expect(b.workDir.existsSync(), isFalse);
        expect(await b.cipher.loadKeys(), isNull);
      });
    }

    test(
      'a crash in the middle of the swap: the files on disk at that '
      'moment open as the OLD database; the aborted swap rolls back',
      () async {
        final before = await fullDump(b.db);
        final file = await backupOfA();
        final crash = Directory('${b.world.root.path}/crash')..createSync();
        var steps = 0;
        await expectLater(
          b
              .service(
                swapPagesPerStep: 4,
                onSwapStep: () {
                  steps++;
                  if (steps == 2) {
                    // Power loss now: copy what is on disk (no -shm: it is
                    // rebuilt on open).
                    for (final n in ['zaghlol.db', 'zaghlol.db-wal']) {
                      final f = File('${b.world.dbDir.path}/$n');
                      if (f.existsSync()) f.copySync('${crash.path}/$n');
                    }
                    throw StateError('killed');
                  }
                },
              )
              .restore(bytesStream(file), passphrase),
          snapCode(BackupSnapshotErrorCode.swapFailed),
        );
        expect(steps, 2, reason: 'the swap must have been mid-way');
        expect(await fullDump(b.db), before);
        final crashed = openedRawDump(File('${crash.path}/zaghlol.db'));
        expect(crashed, before);
      },
    );

    test('a crash after the swap commit, before K_bk is stored: data '
        'restored, next backup asks for the passphrase and recovers', () async {
      final file = await backupOfA();
      await expectLater(
        b
            .service(
              onStep: (s) {
                if (s == 'swapped') throw StateError('crash');
              },
            )
            .restore(bytesStream(file), passphrase),
        throwsStateError,
      );
      expect(
        await dump(b.db, backedUpTables),
        await dump(a.db, backedUpTables),
      );
      await expectLater(
        b.cipher.loadKeys(),
        cryptoCode(BackupCryptoErrorCode.keyMismatch),
      );
      (await b.cipher.recoverWithPassphrase(passphrase)).zeroize();
      final keys = await b.cipher.loadKeys();
      expect(keys!.slot.sameAs(keysA.slot), isTrue);
      keys.zeroize();
    });

    test(
      'leftovers of a crashed run are swept by the next operation',
      () async {
        b.workDir.createSync(recursive: true);
        File('${b.workDir.path}/restore-stage.db').writeAsBytesSync([1, 2, 3]);
        final file = await backupOfA();
        await b.service().restore(bytesStream(file), passphrase);
        expect(b.workDir.existsSync(), isFalse);
      },
    );
  });

  test('one operation at a time: a second call while one runs is busy, and '
      'the first still completes', () async {
    final file = await backupOfA();
    late final BackupSnapshotService service;
    var checked = false;
    service = b.service(
      onStep: (s) {
        if (s == 'staged') {
          checked = true;
          expect(
            service.restore(bytesStream(file), passphrase),
            snapCode(BackupSnapshotErrorCode.busy),
          );
        }
      },
    );
    await service.restore(bytesStream(file), passphrase);
    final writer = service.write(
      keysA,
      seq: 1,
      platform: BackupPlatform.android,
      appVersion: '1',
    );
    expect(await collectBytes(writer), isNotEmpty);
    expect(checked, isTrue);
  });
}

/// Dumps every table of [file] opened raw with phone B's key.
Map<String, List<String>> openedRawDump(File file) {
  final raw = openRaw(file, keyOf(seedB));
  try {
    final names = [
      for (final r in raw.select(
        "SELECT name FROM sqlite_schema WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL%'",
      ))
        r.columnAt(0) as String,
    ];
    return rawDump(raw, names);
  } finally {
    raw.close();
  }
}

Future<int> _countIn(
  DbKeyMaterial key,
  Future<void> Function(Directory dir) make,
  String table,
) async {
  final dir = await Directory.systemTemp.createTemp('zaghlol_t149_cnt_');
  try {
    await make(dir);
    final raw = openRaw(File('${dir.path}/x.db'), key);
    try {
      return raw.select('SELECT count(*) FROM "$table"').first.columnAt(0)
          as int;
    } finally {
      raw.close();
    }
  } finally {
    await dir.delete(recursive: true);
  }
}
