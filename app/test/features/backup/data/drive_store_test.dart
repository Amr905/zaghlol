// T-150: DriveBackupStore against an in-memory Drive app folder (no network,
// no credentials). Safety: an upload is renamed only after Drive's size and
// MD5 match; pruning deletes only our older final names, after a verified
// upload, with a complete listing; foreign files are never touched.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaghlol/features/backup/data/drive_auth.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/data/drive_files.dart';
import 'package:zaghlol/features/backup/data/drive_store.dart';

import 'fake_drive.dart';

Matcher driveCode(DriveBackupErrorCode code) => throwsA(
  isA<DriveBackupException>().having((e) => e.reason, 'reason', code),
);

void main() {
  late Directory tmp;
  late FakeDrive fake;
  late FakeConnector connector;
  late DriveBackupStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('t150store');
    fake = FakeDrive();
    connector = FakeConnector(fake);
    store = DriveBackupStore(connector);
  });

  tearDown(() => tmp.delete(recursive: true));

  Future<LocalBackupFile> local(int seq, {int size = 100000}) async {
    final bytes = Uint8List.fromList(
      List.generate(size, (i) => (i * 7 + seq) & 0xff),
    );
    final f = File('${tmp.path}/b$seq.enc');
    await f.writeAsBytes(bytes);
    return LocalBackupFile(
      file: f,
      length: bytes.length,
      md5Hex: c.md5.convert(bytes).toString(),
      seq: seq,
      createdAtMs: 1700000000000 + seq,
      platform: 'android',
      schemaVersion: 4,
    );
  }

  group('names', () {
    test('final and partial names are strict', () {
      final n = backupFileName(3, 1700000000000);
      expect(n, 'zaghlol-backup-3-1700000000000.zaghlol.enc');
      expect(isBackupFileName(n), isTrue);
      expect(isPartialFileName(partialFileName(n)), isTrue);
      expect(isBackupFileName(partialFileName(n)), isFalse);
      for (final bad in [
        'zaghlol-backup-3-1.zaghlol.enc ',
        'x/zaghlol-backup-3-1.zaghlol.enc',
        'zaghlol-backup-٣-1.zaghlol.enc',
        'zaghlol-backup--1-1.zaghlol.enc',
        'notes.txt',
        'zaghlol-backup-3-1.zaghlol.enc​',
      ]) {
        expect(isBackupFileName(bad), isFalse, reason: bad);
      }
      expect(() => backupFileName(-1, 1), throwsArgumentError);
    });

    test('labels are parsed from name and appProperties, bounded', () {
      final e = DriveBackupEntry.fromFile(
        DriveFile(
          id: 'a',
          name: backupFileName(9, 123),
          size: 5,
          md5: 'm',
          createdTime: DateTime.utc(2026),
          appProperties: const {'platform': 'evil', 'schema': '99999999'},
        ),
      )!;
      expect(e.labelSeq, 9);
      expect(e.labelCreatedAtMs, 123);
      expect(e.labelPlatform, isNull);
      expect(e.labelSchemaVersion, isNull);
      expect(e.toString(), isNot(contains(e.name)));
    });
  });

  group('upload', () {
    test('verified upload: final name, labels, no partial left', () async {
      final e = await store.upload(await local(1));
      expect(fake.names, [backupFileName(1, 1700000000001)]);
      expect(e.labelSeq, 1);
      expect(e.sizeBytes, 100000);
      expect(fake.files[e.id]!.meta.appProperties['platform'], 'android');
      expect(fake.calls, ['create', 'rename']);
    });

    test('AC2: Drive bytes differ (MD5) → not renamed, partial deleted, '
        'previous backup untouched', () async {
      final first = await store.upload(await local(1));
      fake.corruptNextUpload = true;
      await expectLater(
        store.upload(await local(2)),
        driveCode(DriveBackupErrorCode.uploadUnverified),
      );
      expect(fake.names, [first.name]);
      expect(
        fake.files[first.id]!.bytes,
        await (await local(1)).file.readAsBytes(),
      );
    });

    test('AC2: interrupted upload creates nothing; previous kept', () async {
      final first = await store.upload(await local(1));
      fake.dropUploadAfter = 50000;
      await expectLater(
        store.upload(await local(2)),
        driveCode(DriveBackupErrorCode.network),
      );
      expect(fake.names, [first.name]);
      expect(fake.deleted, isEmpty);
    });

    test('rename that does not land → uploadUnverified; previous kept, '
        'complete partial left for the sweep', () async {
      final first = await store.upload(await local(1));
      fake.renameLies = true;
      await expectLater(
        store.upload(await local(2)),
        driveCode(DriveBackupErrorCode.uploadUnverified),
      );
      expect(fake.names, [
        first.name,
        partialFileName(backupFileName(2, 1700000000002)),
      ]);
    });

    test(
      'a 401 refreshes the token once and succeeds; twice → denied',
      () async {
        fake.before = (op, _) {
          if (op == 'create' && fake.refused.isEmpty) {
            fake.expired.add('tok0');
          }
        };
        await store.upload(await local(1));
        expect(fake.refused, ['tok0']);
        expect(fake.names, hasLength(1));

        fake.before = (op, _) => fake.expired.addAll(['tok1', 'tok2', 'tok3']);
        await expectLater(
          store.upload(await local(2)),
          driveCode(DriveBackupErrorCode.authorizationDenied),
        );
        expect(fake.names, hasLength(1));
      },
    );

    test('empty or oversized file refused before any call', () async {
      final l = await local(1);
      await expectLater(
        store.upload(
          LocalBackupFile(
            file: l.file,
            length: maxBackupFileBytes + 1,
            md5Hex: l.md5Hex,
            seq: 1,
            createdAtMs: 1,
            platform: 'android',
            schemaVersion: 4,
          ),
        ),
        driveCode(DriveBackupErrorCode.tooLarge),
      );
      expect(fake.calls, isEmpty);
    });

    test(
      'non-interactive: a needed sign-in surfaces, nothing uploaded',
      () async {
        connector.connectError = DriveBackupErrorCode.signInRequired;
        await expectLater(
          store.upload(await local(1)),
          driveCode(DriveBackupErrorCode.signInRequired),
        );
        expect(connector.interactiveCalls, [false]);
        expect(fake.files, isEmpty);
      },
    );
  });

  group('planPrune', () {
    DriveBackupEntry entryOf(DriveFile f) => DriveBackupEntry.fromFile(f)!;
    const day = Duration(hours: 24);

    test('keeps protect + newest keep; deletes only older final names', () {
      final old = [
        for (var i = 1; i <= 6; i++) fake.seed(backupFileName(i, i), [i]),
      ];
      final foreign = fake.seed('notes.txt', [1]);
      final p = fake.seed(backupFileName(7, 7), [7]);
      final listing = fake.files.values.map((f) => f.meta).toList();
      final plan = planPrune(
        listing: listing,
        protect: entryOf(p),
        keep: 3,
        partialAge: day,
      )!;
      expect(plan.toSet(), {old[0].id, old[1].id, old[2].id, old[3].id});
      expect(plan, isNot(contains(foreign.id)));
      expect(plan, isNot(contains(p.id)));
    });

    test('files created at or after protect (another phone) are kept', () {
      final older = fake.seed(backupFileName(1, 1), [1]);
      final p = fake.seed(backupFileName(2, 2), [2]);
      final newer = fake.seed(backupFileName(3, 3), [3]);
      final same = fake.seed(backupFileName(4, 4), [
        4,
      ], createdTime: p.createdTime);
      final plan = planPrune(
        listing: fake.files.values.map((f) => f.meta).toList(),
        protect: entryOf(p),
        keep: 1,
        partialAge: day,
      )!;
      expect(plan, [older.id]);
      expect(plan, isNot(contains(newer.id)));
      expect(plan, isNot(contains(same.id)));
    });

    test('protect missing, renamed or changed → no plan', () {
      fake.seed(backupFileName(1, 1), [1]);
      final p = fake.seed(backupFileName(2, 2), [2]);
      final listing = fake.files.values.map((f) => f.meta).toList();
      final pe = entryOf(p);
      expect(
        planPrune(
          listing: listing.where((f) => f.id != p.id).toList(),
          protect: pe,
          keep: 1,
          partialAge: day,
        ),
        isNull,
      );
      final changed = DriveFile(
        id: p.id,
        name: p.name,
        size: p.size,
        md5: 'other',
        createdTime: p.createdTime,
      );
      expect(
        planPrune(
          listing: [...listing.where((f) => f.id != p.id), changed],
          protect: pe,
          keep: 1,
          partialAge: day,
        ),
        isNull,
      );
      expect(
        () =>
            planPrune(listing: listing, protect: pe, keep: 0, partialAge: day),
        throwsArgumentError,
      );
    });

    test('undated files are never deleted; partials only when ≥ 24 h older '
        'than protect by the server clock', () {
      final undated = fake.seed(backupFileName(1, 1), [1], dated: false);
      final base = DateTime.utc(2026, 12);
      final stale = fake.seed(partialFileName(backupFileName(2, 2)), [
        2,
      ], createdTime: base.subtract(const Duration(hours: 25)));
      final fresh = fake.seed(partialFileName(backupFileName(3, 3)), [
        3,
      ], createdTime: base.subtract(const Duration(hours: 23)));
      final foreignPartial = fake.seed('other.partial', [
        4,
      ], createdTime: base.subtract(const Duration(days: 9)));
      final p = fake.seed(backupFileName(5, 5), [5], createdTime: base);
      final plan = planPrune(
        listing: fake.files.values.map((f) => f.meta).toList(),
        protect: entryOf(p),
        keep: 1,
        partialAge: day,
      )!;
      expect(plan, [stale.id]);
      expect(plan, isNot(contains(undated.id)));
      expect(plan, isNot(contains(fresh.id)));
      expect(plan, isNot(contains(foreignPartial.id)));
    });
  });

  group('prune', () {
    test(
      'Gold keep 5 after 7 uploads → newest 5; Free keep 1 → one file',
      () async {
        DriveBackupEntry? last;
        for (var i = 1; i <= 7; i++) {
          last = await store.upload(await local(i, size: 10));
        }
        final r = await store.prune(protect: last!, keep: 5);
        expect(r.deleted, 2);
        expect(
          fake.names,
          [for (var i = 3; i <= 7; i++) backupFileName(i, 1700000000000 + i)]
            ..sort(),
        );
        final next = await store.upload(await local(8, size: 10));
        await store.prune(protect: next, keep: 1);
        expect(fake.names, [backupFileName(8, 1700000000008)]);
      },
    );

    test('a list failure on any page → skipped, nothing deleted', () async {
      for (var i = 1; i <= 3; i++) {
        await store.upload(await local(i, size: 10));
      }
      final p = await store.upload(await local(4, size: 10));
      fake.pageSize = 2;
      var lists = 0;
      fake.before = (op, _) {
        if (op == 'list' && ++lists == 2) {
          throw DriveBackupException(DriveBackupErrorCode.network);
        }
      };
      final r = await store.prune(protect: p, keep: 1);
      expect(r.skipped, isTrue);
      expect(r.failure, DriveBackupErrorCode.network);
      expect(fake.deleted, isEmpty);
      expect(fake.names, hasLength(4));
    });

    test('endless paging → listTooLong, nothing deleted', () async {
      await store.upload(await local(1, size: 10));
      final p = await store.upload(await local(2, size: 10));
      fake
        ..pageSize = 1
        ..endlessPages = true;
      final r = await store.prune(protect: p, keep: 1);
      expect(r.skipped, isTrue);
      expect(fake.deleted, isEmpty);
    });

    test('404 counts as gone; another delete error stops pruning', () async {
      for (var i = 1; i <= 3; i++) {
        await store.upload(await local(i, size: 10));
      }
      final p = await store.upload(await local(4, size: 10));
      var n = 0;
      fake.before = (op, id) {
        if (op != 'delete') return;
        n++;
        if (n == 1) {
          fake.files.remove(id);
        } else if (n == 2) {
          throw DriveBackupException(DriveBackupErrorCode.serverError);
        }
      };
      final r = await store.prune(protect: p, keep: 1);
      expect(r.failure, DriveBackupErrorCode.serverError);
      expect(r.deleted, 0);
      expect(fake.names, hasLength(3));
    });
  });

  group('list, download, delete', () {
    test(
      'list: ours only, newest first, partials and foreign excluded',
      () async {
        fake.seed('notes.txt', [1]);
        final a = await store.upload(await local(1, size: 10));
        fake.seed(partialFileName(backupFileName(5, 5)), [1]);
        final b = await store.upload(await local(2, size: 10));
        final l = await store.list();
        expect([for (final e in l) e.id], [b.id, a.id]);
      },
    );

    test('download yields exactly the stored bytes', () async {
      final l = await local(1);
      final e = await store.upload(l);
      final got = <int>[];
      await for (final d in store.download(e)) {
        got.addAll(d);
      }
      expect(got, await l.file.readAsBytes());
    });

    test('download: extra or missing bytes → corruptDownload; foreign name '
        '→ notOurFile; oversized label → tooLarge', () async {
      final e = await store.upload(await local(1, size: 10));
      fake.downloadSkew = 1;
      await expectLater(
        store.download(e).drain<void>(),
        driveCode(DriveBackupErrorCode.corruptDownload),
      );
      fake.downloadSkew = -1;
      await expectLater(
        store.download(e).drain<void>(),
        driveCode(DriveBackupErrorCode.corruptDownload),
      );
      fake.downloadSkew = 0;
      final foreign = DriveBackupEntry(
        id: e.id,
        name: 'notes.txt',
        sizeBytes: 10,
        md5: e.md5,
        serverCreatedAt: e.serverCreatedAt,
        labelSeq: 1,
        labelCreatedAtMs: 1,
      );
      await expectLater(
        store.download(foreign).drain<void>(),
        driveCode(DriveBackupErrorCode.notOurFile),
      );
      final huge = DriveBackupEntry(
        id: e.id,
        name: e.name,
        sizeBytes: maxBackupFileBytes + 1,
        md5: e.md5,
        serverCreatedAt: e.serverCreatedAt,
        labelSeq: 1,
        labelCreatedAtMs: 1,
      );
      await expectLater(
        store.download(huge).drain<void>(),
        driveCode(DriveBackupErrorCode.tooLarge),
      );
    });

    test('a stalled download times out as network', () async {
      final e = await store.upload(await local(1, size: 10));
      final slow = DriveBackupStore(
        connector,
        downloadIdleTimeout: const Duration(milliseconds: 50),
      );
      fake.before = (op, _) async {
        if (op == 'download') {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      };
      await expectLater(
        slow.download(e).drain<void>(),
        driveCode(DriveBackupErrorCode.network),
      );
    });

    test(
      'delete: only an id that carries that backup name right now',
      () async {
        final foreign = fake.seed('notes.txt', [1]);
        final e = await store.upload(await local(1, size: 10));
        final forged = DriveBackupEntry(
          id: foreign.id,
          name: e.name,
          sizeBytes: 1,
          md5: null,
          serverCreatedAt: null,
          labelSeq: 1,
          labelCreatedAtMs: 1,
        );
        await expectLater(
          store.delete(forged),
          driveCode(DriveBackupErrorCode.notOurFile),
        );
        expect(fake.files.containsKey(foreign.id), isTrue);
        await store.delete(e);
        expect(fake.names, ['notes.txt']);
      },
    );

    test('one operation at a time', () async {
      final gate = Completer<void>();
      fake.before = (op, _) => op == 'list' ? gate.future : null;
      final first = store.list();
      await expectLater(store.list(), driveCode(DriveBackupErrorCode.busy));
      gate.complete();
      await first;
    });
  });

  group('adapter', () {
    test('Drive errors map to codes and never echo the server text', () async {
      Future<DriveBackupErrorCode> answer(int status, [String? reason]) async {
        final client = MockClient(
          (_) async => http.Response(
            '{"error":{"code":$status,"message":"secret server message",'
            '"errors":[${reason == null ? '' : '{"reason":"$reason","message":"secret"}'}]}}',
            status,
            headers: {'content-type': 'application/json'},
          ),
        );
        final files = GoogleapisDriveFiles(BearerClient('t', client));
        try {
          await files.delete('x');
          fail('no error');
        } on DriveBackupException catch (e) {
          expect(e.toString(), isNot(contains('secret')));
          return e.reason;
        } finally {
          files.close();
        }
      }

      expect(await answer(401), DriveBackupErrorCode.authExpired);
      expect(await answer(404), DriveBackupErrorCode.notFound);
      expect(
        await answer(403, 'storageQuotaExceeded'),
        DriveBackupErrorCode.quotaExceeded,
      );
      expect(
        await answer(403, 'userRateLimitExceeded'),
        DriveBackupErrorCode.rateLimited,
      );
      expect(await answer(429), DriveBackupErrorCode.rateLimited);
      expect(await answer(403), DriveBackupErrorCode.authorizationDenied);
      expect(await answer(503), DriveBackupErrorCode.serverError);
      expect(
        classifyDriveError(const SocketException('x')),
        DriveBackupErrorCode.network,
      );
      expect(
        classifyDriveError(TimeoutException('x')),
        DriveBackupErrorCode.network,
      );
      expect(
        classifyDriveError(http.ClientException('x')),
        DriveBackupErrorCode.network,
      );
    });

    test('list request is pinned to appDataFolder and carries the bearer '
        'token; errors carry no token', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          '{"error":{"code":401,"message":"tokABC bad"}}',
          401,
          headers: {'content-type': 'application/json'},
        );
      });
      final files = GoogleapisDriveFiles(BearerClient('tokABC', client));
      Object? caught;
      try {
        await files.list();
      } on Object catch (e) {
        caught = e;
      }
      expect(seen.headers['Authorization'], 'Bearer tokABC');
      expect(seen.url.queryParameters['spaces'], appDataFolder);
      expect(
        seen.url.queryParameters['q'],
        "'appDataFolder' in parents and trashed = false",
      );
      expect(
        caught,
        isA<DriveBackupException>().having(
          (e) => e.reason,
          'reason',
          DriveBackupErrorCode.authExpired,
        ),
      );
      expect(caught.toString(), isNot(contains('tokABC')));
      expect(BearerClient('tokABC', client).toString(), isNot(contains('tok')));
      files.close();
    });

    test('create uses a resumable upload into appDataFolder', () async {
      final requests = <http.BaseRequest>[];
      final bodies = <String>[];
      final client = MockClient.streaming((req, body) async {
        requests.add(req);
        bodies.add(await body.bytesToString());
        if (req.url.queryParameters['uploadType'] == 'resumable' &&
            req.method == 'POST') {
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'location': 'https://upload.example/session1'},
          );
        }
        return http.StreamedResponse(
          Stream.value(
            '{"id":"f1","name":"n.partial","size":"3","md5Checksum":"abc"}'
                .codeUnits,
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final files = GoogleapisDriveFiles(BearerClient('t', client));
      final f = await files.create(
        name: 'n.partial',
        appProperties: const {'zglb': '1'},
        media: Stream.value([1, 2, 3]),
        length: 3,
      );
      expect(f.id, 'f1');
      expect(f.size, 3);
      expect(requests.first.url.queryParameters['uploadType'], 'resumable');
      expect(bodies.first, contains('"parents":["appDataFolder"]'));
      files.close();
    });
  });
}
