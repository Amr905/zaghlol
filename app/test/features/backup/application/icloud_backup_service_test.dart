// T-151: back up to iCloud and restore from iCloud, end to end on real
// encrypted databases (two synthetic phones, T-149 harness) and an
// in-memory iCloud container. AC: iCloud off → clear error and Drive offer.
// Plus the T-150 safety rules: verify, then wait for "uploaded", then prune.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/application/icloud_backup_service.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart'
    show backupFileName;
import 'package:zaghlol/features/backup/data/icloud_backup_exception.dart';
import 'package:zaghlol/features/backup/data/icloud_store.dart';
import 'package:zaghlol/features/backup/data/secure_state_seq_store.dart';

import '../data/fake_icloud.dart';
import 'snapshot_test_support.dart';

Matcher iCloudCode(ICloudBackupErrorCode code) => throwsA(
  isA<ICloudBackupException>().having((e) => e.reason, 'reason', code),
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late Phone a;
  late Phone b;
  late BackupKeys keysA;
  late FakeICloud cloud;

  setUp(() async {
    a = await Phone.create(seedA, 't151a');
    b = await Phone.create(seedB, 't151b');
    await populateSource(a.db);
    await populateTarget(b.db);
    keysA = await a.cipher.createKey(passphrase);
    cloud = FakeICloud(a.world.tempDir);
  });

  tearDown(() async {
    keysA.zeroize();
    await a.dispose();
    await b.dispose();
  });

  ICloudBackupService serviceOf(
    Phone p, {
    FakeICloud? container,
    void Function(String)? onStep,
  }) => ICloudBackupService(
    snapshot: p.service(onStep: onStep),
    cipher: p.cipher,
    store: ICloudBackupStore(container ?? cloud),
    seq: SecureStateSeqStore(() async => p.db),
    tempDirectory: () async => p.world.tempDir,
    uploadWait: const Duration(milliseconds: 200),
    uploadPoll: const Duration(milliseconds: 5),
  );

  Future<ICloudBackupOutcome> backupA({
    int keep = 5,
    ICloudBackupService? service,
  }) => (service ?? serviceOf(a)).backupNow(
    keysA,
    keep: keep,
    platform: BackupPlatform.ios,
    appVersion: '1.0.0+1',
    chunkSize: minChunkSize,
  );

  Directory uploadDir(Phone p) =>
      Directory('${p.world.tempDir.path}/$iCloudUploadDirName');

  test('AC: iCloud off → ICLOUD_UNAVAILABLE that offers Drive; nothing is '
      'written, uploaded or deleted', () async {
    await backupA(keep: 1);
    final before = cloud.names;
    cloud.available = false;
    cloud.calls.clear();
    final svc = serviceOf(a);
    expect(await svc.isAvailable(), isFalse);
    Object? err;
    try {
      await backupA(keep: 1, service: svc);
    } on Object catch (e) {
      err = e;
    }
    expect(
      err,
      isA<ICloudBackupException>()
          .having((e) => e.reason, 'reason', ICloudBackupErrorCode.unavailable)
          .having((e) => e.offersDrive, 'offersDrive', isTrue)
          .having((e) => e.code, 'code', 'ICLOUD_UNAVAILABLE'),
    );
    expect(cloud.calls, isEmpty);
    expect(await uploadDir(a).exists(), isFalse);
    await expectLater(
      svc.list(),
      iCloudCode(ICloudBackupErrorCode.unavailable),
    );
    cloud.available = true;
    expect(cloud.names, before);
  });

  test('an iPhone backup in iCloud restores on the other phone, data '
      'identical; only ciphertext reaches iCloud', () async {
    final source = await dump(a.db, backedUpTables);
    final out = await backupA();
    expect(out.uploaded, isTrue);
    expect(out.entry.labelSeq, 1);
    expect(out.seqStored, isTrue);
    expect(await uploadDir(a).exists(), isFalse);
    final stored = latin1.decode(cloud.files.values.single.bytes);
    for (final s in [noteSentinel, smsSentinel, settingSentinel]) {
      expect(stored.contains(s), isFalse);
    }

    final onB = serviceOf(b);
    final listed = await onB.list();
    expect(listed, hasLength(1));
    final restored = await onB.restore(listed.single, passphrase);
    expect(restored.platform, BackupPlatform.ios);
    expect(restored.seq, 1);
    expect(await dump(b.db, backedUpTables), source);
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

  test('not yet uploaded → nothing pruned; the next uploaded run prunes the '
      'leftovers', () async {
    final first = await backupA(keep: 1);
    cloud.uploadAfterLists = null; // iCloud keeps "uploading"
    final second = await backupA(keep: 1);
    expect(second.uploaded, isFalse);
    expect(second.prune.skipped, isTrue);
    expect(cloud.names, [first.entry.name, second.entry.name]..sort());
    expect(cloud.deleted, isEmpty);

    cloud.uploadAfterLists = 0;
    final third = await backupA(keep: 1);
    expect(third.uploaded, isTrue);
    expect(cloud.names, [third.entry.name]);
  });

  test('iCloud full: the new backup is refused, the previous one stays, and '
      'the next run refuses up front', () async {
    final first = await backupA(keep: 1);
    cloud.quotaOnNext = true;
    await expectLater(
      backupA(keep: 1),
      iCloudCode(ICloudBackupErrorCode.quotaExceeded),
    );
    expect(cloud.names, contains(first.entry.name));
    expect(cloud.deleted, isEmpty);
    final uploads = cloud.calls.where((c) => c == 'upload').length;
    await expectLater(
      backupA(keep: 1),
      iCloudCode(ICloudBackupErrorCode.quotaExceeded),
    );
    expect(cloud.calls.where((c) => c == 'upload').length, uploads);
    expect(await uploadDir(a).exists(), isFalse);
  });

  test(
    'stored bytes differ → uploadUnverified, previous kept, no prune',
    () async {
      final first = await backupA(keep: 1);
      cloud.corruptNextUpload = true;
      await expectLater(
        backupA(keep: 1),
        iCloudCode(ICloudBackupErrorCode.uploadUnverified),
      );
      expect(cloud.names, contains(first.entry.name));
      expect(cloud.deleted, isEmpty);
    },
  );

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
    expect(cloud.calls.where((c) => c == 'upload'), hasLength(1));
    expect(cloud.deleted, isEmpty);
    expect(await uploadDir(a).exists(), isFalse);
  });

  test(
    'two phones back up at once with keep 1: the newest backup survives',
    () async {
      final keysB = await b.cipher.createKey(passphrase);
      addTearDown(keysB.zeroize);
      await backupA(keep: 1);
      // Distinct names (the harness clock is fixed); a clash would only be
      // refused (ALREADY_EXISTS), never overwritten.
      await SecureStateSeqStore(() async => b.db).write(10);
      // Phone A's prune listing (its third) waits until phone B has finished.
      final gate = Completer<void>();
      var aLists = 0;
      cloud.before = (op, name) async {
        if (op == 'list' && ++aLists == 3) await gate.future;
      };
      final runA = backupA(keep: 1);
      while (aLists < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      cloud.before = null;
      final outB = await serviceOf(b).backupNow(
        keysB,
        keep: 1,
        platform: BackupPlatform.ios,
        appVersion: '1.0.0+1',
        chunkSize: minChunkSize,
      );
      gate.complete();
      final outA = await runA;
      // B kept its own upload and pruned A's older one; A then no longer
      // finds its protect and deletes nothing.
      expect(outB.prune.deleted, 2);
      expect(outA.prune.skipped, isTrue);
      expect(cloud.names, [outB.entry.name]);
    },
  );

  test('seq continues above the listed labels', () async {
    cloud.seed(backupFileName(41, 5), [1]);
    expect((await backupA()).entry.labelSeq, 42);
  });
}
