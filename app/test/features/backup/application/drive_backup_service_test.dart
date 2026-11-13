// T-150: backup to Drive and restore from Drive, end to end on real
// encrypted databases (two synthetic phones, T-149 harness) and an in-memory
// Drive app folder. AC1: an Android backup restores on the other phone via
// Drive. AC2: a partial or unverified upload never replaces the previous
// backup and never triggers pruning.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/application/drive_backup_service.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart';
import 'package:zaghlol/features/backup/data/secure_state_seq_store.dart';

import '../data/fake_drive.dart';
import 'snapshot_test_support.dart';

Matcher driveCode(DriveBackupErrorCode code) => throwsA(
  isA<DriveBackupException>().having((e) => e.reason, 'reason', code),
);

final class MemorySeqStore implements BackupSeqStore {
  int? value;
  bool failWrite = false;

  @override
  Future<int?> read() async => value;

  @override
  Future<void> write(int seq) async {
    if (failWrite) throw StateError('x');
    value = seq;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Phone a;
  late Phone b;
  late BackupKeys keysA;
  late FakeDrive cloud;

  setUp(() async {
    a = await Phone.create(seedA, 't150a');
    b = await Phone.create(seedB, 't150b');
    await populateSource(a.db);
    await populateTarget(b.db);
    keysA = await a.cipher.createKey(passphrase);
    cloud = FakeDrive();
  });

  tearDown(() async {
    keysA.zeroize();
    await a.dispose();
    await b.dispose();
  });

  DriveBackupService serviceOf(
    Phone p, {
    BackupSeqStore? seq,
    void Function(String)? onStep,
  }) => DriveBackupService(
    snapshot: p.service(onStep: onStep),
    cipher: p.cipher,
    store: DriveBackupStore(FakeConnector(cloud)),
    seq: seq ?? SecureStateSeqStore(() async => p.db),
    tempDirectory: () async => p.world.tempDir,
  );

  Future<DriveBackupOutcome> backupA({
    int keep = 5,
    DriveBackupService? service,
  }) => (service ?? serviceOf(a)).backupNow(
    keysA,
    keep: keep,
    platform: BackupPlatform.android,
    appVersion: '1.0.0+1',
    chunkSize: minChunkSize,
  );

  Directory uploadDir(Phone p) =>
      Directory('${p.world.tempDir.path}/$backupUploadDirName');

  test('AC1: Android backup uploaded to Drive restores on the other phone '
      '(listing → download → T-149 restore), data identical', () async {
    final source = await dump(a.db, backedUpTables);
    final out = await backupA();
    expect(out.entry.labelSeq, 1);
    expect(out.entry.labelPlatform, 'android');
    expect(out.seqStored, isTrue);
    expect(out.prune.deleted, 0);
    expect(await uploadDir(a).exists(), isFalse);

    // Phone B (the iPhone side of the AC) sees it through its own listing.
    final onB = serviceOf(b);
    final listed = await onB.list();
    expect(listed, hasLength(1));
    final restored = await onB.restore(listed.single, passphrase);
    expect(restored.platform, BackupPlatform.android);
    expect(restored.seq, 1);
    expect(restored.keyStored, isTrue);
    expect(await dump(b.db, backedUpTables), source);
  });

  test('only ciphertext reaches Drive and the temp dir', () async {
    String? seen;
    final svc = serviceOf(
      a,
      onStep: (s) {
        if (s == 'encrypted') {
          // The staging file is complete here; nothing readable in it.
          for (final f in uploadDir(a).listSync().whereType<File>()) {
            seen = latin1.decode(f.readAsBytesSync());
          }
        }
      },
    );
    await backupA(service: svc);
    expect(seen, isNotNull);
    final uploaded = latin1.decode(cloud.files.values.single.bytes);
    for (final text in [seen!, uploaded]) {
      for (final s in [noteSentinel, smsSentinel, settingSentinel]) {
        expect(text.contains(s), isFalse);
      }
    }
  });

  test('AC2: an interrupted upload leaves the previous backup as it was and '
      'prunes nothing; the staging file is removed', () async {
    final first = await backupA(keep: 1);
    final before = cloud.files[first.entry.id]!.bytes;
    cloud.dropUploadAfter = 70000;
    await expectLater(
      backupA(keep: 1),
      driveCode(DriveBackupErrorCode.network),
    );
    expect(cloud.names, [first.entry.name]);
    expect(cloud.files[first.entry.id]!.bytes, before);
    expect(cloud.deleted, isEmpty);
    expect(await uploadDir(a).exists(), isFalse);
  });

  test('AC2: Drive stored different bytes → not renamed, previous kept, no '
      'prune', () async {
    final first = await backupA(keep: 1);
    cloud.corruptNextUpload = true;
    await expectLater(
      backupA(keep: 1),
      driveCode(DriveBackupErrorCode.uploadUnverified),
    );
    expect(cloud.names, [first.entry.name]);
    // Only the bad partial itself was deleted.
    expect(cloud.deleted, hasLength(1));
    expect(cloud.deleted.single, isNot(first.entry.id));
  });

  test('a snapshot failure uploads nothing and deletes nothing', () async {
    await backupA(keep: 1);
    final svc = serviceOf(
      a,
      onStep: (s) {
        if (s == 'snapshot') throw StateError('boom');
      },
    );
    await expectLater(backupA(keep: 1, service: svc), throwsStateError);
    expect(cloud.names, hasLength(1));
    expect(cloud.calls.where((c) => c == 'create'), hasLength(1));
    expect(cloud.deleted, isEmpty);
    expect(await uploadDir(a).exists(), isFalse);
  });

  test('Free twice → one file; Gold 7 times keep 5 → newest 5', () async {
    await backupA(keep: 1);
    final second = await backupA(keep: 1);
    expect(cloud.names, [second.entry.name]);
    expect(second.prune.deleted, 1);

    for (var i = 0; i < 6; i++) {
      await backupA(keep: 5);
    }
    final seqs = [for (final e in await serviceOf(a).list()) e.labelSeq];
    expect(seqs, [8, 7, 6, 5, 4]);
  });

  test('seq: max(stored, highest listed) + 1, stored after the upload; a '
      'failed store is reported, not fatal', () async {
    final mem = MemorySeqStore()..value = 3;
    final svc = serviceOf(a, seq: mem);
    expect((await backupA(service: svc)).entry.labelSeq, 4);
    expect(mem.value, 4);

    // A restored phone (counter 0) continues above the Drive labels.
    cloud.seed(backupFileName(41, 5), [1]);
    final fresh = MemorySeqStore();
    final out = await backupA(service: serviceOf(a, seq: fresh));
    expect(out.entry.labelSeq, 42);

    // A huge (unauthenticated) label is ignored.
    cloud.seed(backupFileName(1 << 50, 6), [1]);
    final failing = MemorySeqStore()
      ..value = 42
      ..failWrite = true;
    final out2 = await backupA(service: serviceOf(a, seq: failing));
    expect(out2.entry.labelSeq, 43);
    expect(out2.seqStored, isFalse);

    // The DB-backed store round-trips.
    final db = SecureStateSeqStore(() async => a.db);
    await db.write(7);
    expect(await db.read(), 7);
  });

  test(
    'two phones back up at once with keep 1: the newest backup survives',
    () async {
      final keysB = await b.cipher.createKey(passphrase);
      addTearDown(keysB.zeroize);
      // Both uploads finish before either prune lists.
      var renames = 0;
      final bothRenamed = Completer<void>();
      cloud.before = (op, _) async {
        if (op == 'rename' && ++renames == 2) bothRenamed.complete();
        if (op == 'list' && renames > 0) await bothRenamed.future;
      };
      final results = await Future.wait([
        backupA(keep: 1),
        serviceOf(b).backupNow(
          keysB,
          keep: 1,
          platform: BackupPlatform.ios,
          appVersion: '1.0.0+1',
          chunkSize: minChunkSize,
        ),
      ]);
      final newest = results
          .map((r) => r.entry)
          .reduce(
            (x, y) => x.serverCreatedAt!.isAfter(y.serverCreatedAt!) ? x : y,
          );
      expect(cloud.names, contains(newest.name));
      expect(cloud.names, hasLength(1));
    },
  );

  test('one backup at a time per service', () async {
    final svc = serviceOf(a);
    final gate = Completer<void>();
    cloud.before = (op, _) => op == 'list' ? gate.future : null;
    final first = backupA(service: svc);
    await expectLater(
      backupA(service: svc),
      driveCode(DriveBackupErrorCode.busy),
    );
    gate.complete();
    await first;
    expect(
      () => svc.backupNow(
        keysA,
        keep: 0,
        platform: BackupPlatform.android,
        appVersion: '1',
      ),
      throwsArgumentError,
    );
  });

  test('a failed restore download leaves phone B unchanged', () async {
    await backupA();
    final before = await dump(b.db, [...backedUpTables, ...deviceTables]);
    final onB = serviceOf(b);
    final entry = (await onB.list()).single;
    cloud.downloadSkew = -1;
    await expectLater(onB.restore(entry, passphrase), throwsA(anything));
    expect(await dump(b.db, [...backedUpTables, ...deviceTables]), before);
  });
}
