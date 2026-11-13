// T-151: the iCloud store against an in-memory container, the prune plan on
// its own, and the Pigeon adapter through a fake platform (mock binary
// messenger): codes cross, native messages don't.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/icloud_api.g.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart';
import 'package:zaghlol/features/backup/data/icloud_backup_exception.dart';
import 'package:zaghlol/features/backup/data/icloud_store.dart';

import 'fake_icloud.dart';

Matcher iCloudCode(ICloudBackupErrorCode code) => throwsA(
  isA<ICloudBackupException>().having((e) => e.reason, 'reason', code),
);

BackupMeta meta(
  String name, {
  int? size = 10,
  int? at,
  bool up = true,
  bool quota = false,
  bool failed = false,
}) => BackupMeta(
  name: name,
  sizeBytes: size,
  createdAtMs: at,
  isUploaded: up,
  isDownloaded: true,
  quotaExceeded: quota,
  uploadFailed: failed,
);

String n(int seq) => backupFileName(seq, 1000 + seq);

const int hour = 3600000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeICloud cloud;
  late ICloudBackupStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('t151store');
    cloud = FakeICloud(tmp);
    store = ICloudBackupStore(cloud);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<LocalBackupFile> local(int seq, List<int> bytes) async {
    final f = File('${tmp.path}/l$seq.zaghlol.enc');
    await f.writeAsBytes(bytes);
    return LocalBackupFile(
      file: f,
      length: bytes.length,
      md5Hex: c.md5.convert(bytes).toString(),
      seq: seq,
      createdAtMs: 1000 + seq,
      platform: 'ios',
      schemaVersion: 1,
    );
  }

  ICloudBackupEntry entryOf(BackupMeta m) => ICloudBackupEntry.fromMeta(m)!;

  group('planICloudPrune', () {
    final protect = entryOf(meta(n(5), at: 50 * hour));

    test('keeps protect, everything at or after it and the newest keep; '
        'deletes older finals and ignores foreign names', () {
      final listing = [
        meta(n(5), at: 50 * hour),
        meta(n(4), at: 40 * hour),
        meta(n(3), at: 30 * hour),
        meta(n(9), at: 60 * hour, up: false), // another phone, newer
        meta('notes.zaghlol.enc', at: 1),
        meta(n(2)), // undated
      ];
      final plan = planICloudPrune(
        listing: listing,
        protect: protect,
        keep: 1,
        partialAge: const Duration(hours: 24),
      );
      expect(plan, unorderedEquals([n(4), n(3)]));
      expect(
        planICloudPrune(
          listing: listing,
          protect: protect,
          keep: 3,
          partialAge: const Duration(hours: 24),
        ),
        [n(3)],
      );
    });

    test('nothing when protect is not uploaded, missing, resized, refused '
        'or undated', () {
      for (final p in [
        meta(n(5), at: 50 * hour, up: false),
        meta(n(5), at: 50 * hour, size: 11),
        meta(n(5), at: 50 * hour, size: null),
        meta(n(5), at: 50 * hour, quota: true),
        meta(n(5), at: 50 * hour, failed: true),
        meta(n(5)),
        meta(n(6), at: 50 * hour),
      ]) {
        expect(
          planICloudPrune(
            listing: [
              p,
              meta(n(1), at: hour),
            ],
            protect: protect,
            keep: 1,
            partialAge: const Duration(hours: 24),
          ),
          isNull,
          reason: '$p',
        );
      }
    });

    test('partials only when ≥ 24 h older than protect', () {
      final listing = [
        meta(n(5), at: 50 * hour),
        meta('${n(1)}.partial', at: 26 * hour),
        meta('${n(2)}.partial', at: 27 * hour),
        meta('${n(3)}.partial'),
      ];
      expect(
        planICloudPrune(
          listing: listing,
          protect: protect,
          keep: 1,
          partialAge: const Duration(hours: 24),
        ),
        ['${n(1)}.partial'],
      );
    });
  });

  group('upload', () {
    test('verified: name, size and MD5 match the local file', () async {
      final e = await store.upload(await local(3, [1, 2, 3]));
      expect(e.name, n(3));
      expect(e.sizeBytes, 3);
      expect(cloud.names, [n(3)]);
    });

    test('MD5 mismatch → uploadUnverified', () async {
      cloud.corruptNextUpload = true;
      await expectLater(
        store.upload(await local(3, [1, 2, 3])),
        iCloudCode(ICloudBackupErrorCode.uploadUnverified),
      );
    });

    test('iCloud off → unavailable, offers Drive, nothing sent', () async {
      cloud.available = false;
      Object? err;
      try {
        await store.upload(await local(3, [1, 2, 3]));
      } on ICloudBackupException catch (e) {
        err = e;
      }
      expect(err, isA<ICloudBackupException>());
      final e = err! as ICloudBackupException;
      expect(e.reason, ICloudBackupErrorCode.unavailable);
      expect(e.offersDrive, isTrue);
      expect(e.toString(), contains('ICLOUD_UNAVAILABLE'));
      expect(cloud.calls, isEmpty);
      await expectLater(
        store.list(),
        iCloudCode(ICloudBackupErrorCode.unavailable),
      );
      expect(
        ICloudBackupException(ICloudBackupErrorCode.timeout).offersDrive,
        isFalse,
      );
    });
  });

  group('waitUploaded', () {
    test('returns the entry once iCloud reports it uploaded', () async {
      cloud.uploadAfterLists = 2;
      final e = await store.upload(await local(3, [1, 2, 3]));
      final up = await store.waitUploaded(e, interval: Duration.zero);
      expect(up?.isUploaded, isTrue);
    });

    test('null when it never uploads in time', () async {
      cloud.uploadAfterLists = null;
      final e = await store.upload(await local(3, [1, 2, 3]));
      expect(
        await store.waitUploaded(
          e,
          timeout: const Duration(milliseconds: 30),
          interval: const Duration(milliseconds: 5),
        ),
        isNull,
      );
    });

    test('quota refusal → quotaExceeded', () async {
      cloud.quotaOnNext = true;
      final e = await store.upload(await local(3, [1, 2, 3]));
      await expectLater(
        store.waitUploaded(e, interval: Duration.zero),
        iCloudCode(ICloudBackupErrorCode.quotaExceeded),
      );
    });
  });

  group('prune', () {
    Future<ICloudBackupEntry> uploaded(int seq) async {
      final e = await store.upload(await local(seq, [seq, 1, 2]));
      return (await store.waitUploaded(e, interval: Duration.zero))!;
    }

    test('a listing failure deletes nothing', () async {
      cloud.seed(n(1), [1]);
      final p = await uploaded(2);
      cloud.before = (op, _) {
        if (op == 'list') throw ICloudBackupException(ICloudBackupErrorCode.io);
      };
      final r = await store.prune(protect: p, keep: 1);
      expect(r.skipped, isTrue);
      expect(r.failure, ICloudBackupErrorCode.io);
      expect(cloud.deleted, isEmpty);
    });

    test('a not-yet-uploaded protect deletes nothing', () async {
      cloud.seed(n(1), [1]);
      cloud.uploadAfterLists = null;
      final e = await store.upload(await local(2, [1, 2]));
      final r = await store.prune(protect: e, keep: 1);
      expect(r.skipped, isTrue);
      expect(cloud.names, [n(1), n(2)]);
    });

    test('NOT_FOUND counts as gone; another error stops pruning', () async {
      cloud.seed(n(1), [1]);
      cloud.seed(n(2), [1]);
      cloud.seed(n(3), [1]);
      final p = await uploaded(4);
      cloud.before = (op, name) {
        if (op == 'delete' && name == n(3)) {
          throw ICloudBackupException(ICloudBackupErrorCode.notFound);
        }
        if (op == 'delete' && name == n(2)) {
          throw ICloudBackupException(ICloudBackupErrorCode.io);
        }
      };
      final r = await store.prune(protect: p, keep: 1);
      expect(r.failure, ICloudBackupErrorCode.io);
      expect(r.deleted, 0);
      expect(cloud.names, containsAll([n(1), n(2), n(4)]));
    });
  });

  group('download', () {
    test('streams the listed size and deletes the temp copy', () async {
      cloud.seed(n(1), [1, 2, 3, 4]);
      final e = (await store.list()).single;
      final got = await store.download(e).expand((b) => b).toList();
      expect(got, [1, 2, 3, 4]);
      final dir = Directory('${tmp.path}/zaghlol_backup_download');
      expect(dir.listSync(), isEmpty);
    });

    test('a size different from the listing → corruptDownload', () async {
      cloud.seed(n(1), [1, 2, 3, 4]);
      final e = (await store.list()).single;
      cloud.files[n(1)]!.bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await expectLater(
        store.download(e).toList(),
        iCloudCode(ICloudBackupErrorCode.corruptDownload),
      );
      cloud.files[n(1)]!.bytes = Uint8List.fromList([1, 2]);
      await expectLater(
        store.download(e).toList(),
        iCloudCode(ICloudBackupErrorCode.corruptDownload),
      );
    });
  });

  test('delete refuses names that are not ours and missing files', () async {
    cloud.seed('notes.txt', [1]);
    const foreign = ICloudBackupEntry(
      name: 'notes.txt',
      sizeBytes: 1,
      createdAtMs: 1,
      isUploaded: true,
      isDownloaded: true,
      quotaExceeded: false,
      uploadFailed: false,
      labelSeq: 1,
      labelCreatedAtMs: 1,
    );
    await expectLater(
      store.delete(foreign),
      iCloudCode(ICloudBackupErrorCode.notOurFile),
    );
    final missing = ICloudBackupEntry.fromMeta(meta(n(1), at: 1))!;
    await expectLater(
      store.delete(missing),
      iCloudCode(ICloudBackupErrorCode.notFound),
    );
    expect(cloud.deleted, isEmpty);
    expect(ICloudBackupEntry.fromMeta(meta('notes.zaghlol.enc')), isNull);
    expect(ICloudBackupEntry.fromMeta(meta('${n(1)}.partial')), isNull);
  });

  test('more than 1000 listed files → listTooLong, nothing pruned', () async {
    for (var i = 1; i <= 1001; i++) {
      cloud.seed(n(i), [1], createdAtMs: i * hour);
    }
    await expectLater(
      store.list(),
      iCloudCode(ICloudBackupErrorCode.listTooLong),
    );
  });

  group('PigeonICloudFiles over a fake platform channel', () {
    const prefix = 'dev.flutter.pigeon.zaghlol.ICloudBackupHostApi.';
    const codec = ICloudBackupHostApi.pigeonChannelCodec;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final seen = <String, Object?>{};

    void handle(String method, List<Object?> Function(Object? args) reply) {
      messenger.setMockMessageHandler('$prefix$method', (data) async {
        final args = codec.decodeMessage(data);
        seen[method] = args;
        return codec.encodeMessage(reply(args));
      });
    }

    tearDown(() {
      for (final m in ['isAvailable', 'upload', 'list', 'download', 'delete']) {
        messenger.setMockMessageHandler('$prefix$m', null);
      }
    });

    test('values cross both ways', () async {
      final files = PigeonICloudFiles();
      handle('isAvailable', (_) => [true]);
      handle(
        'list',
        (_) => [
          [meta(n(1), at: 5)],
        ],
      );
      handle('upload', (_) => [meta(n(2), at: 6)..md5 = 'ab']);
      handle('download', (_) => ['/tmp/zaghlol_backup_download/x.zaghlol.enc']);
      handle('delete', (_) => [null]);
      expect(await files.isAvailable(), isTrue);
      expect((await files.list()).single.name, n(1));
      expect((await files.upload('/p', n(2))).md5, 'ab');
      expect(seen['upload'], ['/p', n(2)]);
      expect(await files.download(n(1)), endsWith('.zaghlol.enc'));
      await files.delete(n(1));
      expect(seen['delete'], [n(1)]);
    });

    test('native errors become code-only exceptions', () async {
      final files = PigeonICloudFiles();
      const secret = 'SECRETNATIVEMESSAGE';
      final cases = {
        'ICLOUD_UNAVAILABLE': ICloudBackupErrorCode.unavailable,
        'NOT_FOUND': ICloudBackupErrorCode.notFound,
        'ALREADY_EXISTS': ICloudBackupErrorCode.uploadUnverified,
        'UPLOAD_UNVERIFIED': ICloudBackupErrorCode.uploadUnverified,
        'TOO_LARGE': ICloudBackupErrorCode.tooLarge,
        'TIMEOUT': ICloudBackupErrorCode.timeout,
        'INVALID_ARGUMENT': ICloudBackupErrorCode.notOurFile,
        'IO_ERROR': ICloudBackupErrorCode.io,
        'SOMETHING_NEW': ICloudBackupErrorCode.io,
      };
      for (final e in cases.entries) {
        handle('delete', (_) => [e.key, secret, secret]);
        Object? err;
        try {
          await files.delete(n(1));
        } on Object catch (x) {
          err = x;
        }
        expect(
          err,
          isA<ICloudBackupException>().having(
            (x) => x.reason,
            'reason',
            e.value,
          ),
        );
        expect(err.toString(), isNot(contains(secret)));
      }
      // No handler at all (Android, or not registered) → io.
      messenger.setMockMessageHandler('${prefix}list', null);
      await expectLater(files.list(), iCloudCode(ICloudBackupErrorCode.io));
    });
  });
}
