// T-149 design note §1: contents v1 container, strict decode.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/application/backup_contents.dart';
import 'package:zaghlol/features/backup/application/backup_snapshot_exception.dart';

Matcher get corrupt => throwsA(
  isA<BackupSnapshotException>().having(
    (e) => e.reason,
    'reason',
    BackupSnapshotErrorCode.corruptContents,
  ),
);

Uint8List snapBytes([int n = 8192]) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) & 0xff]);

Uint8List header(String name, int size) {
  final b = BytesBuilder()
    ..addByte(name.length)
    ..add(name.codeUnits);
  final s = ByteData(8)..setUint64(0, size);
  b.add(s.buffer.asUint8List());
  return b.takeBytes();
}

Future<Uint8List> collect(Stream<List<int>> s) async {
  final b = BytesBuilder();
  await for (final e in s) {
    b.add(e);
  }
  return b.takeBytes();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('t149c_'));
  tearDown(() => dir.delete(recursive: true));

  final settings = encodeSettings({'language': 'ar', 'digits': 'auto'});
  final manifest = SnapshotManifest(
    contentsVersion: 1,
    schemaVersion: 4,
    snapshotBytes: 8192,
    settingsBytes: settings.length,
    tables: {'transactions': 3, 'settings': 2},
  ).encode();

  Future<Uint8List> valid() async {
    final f = File('${dir.path}/in.db')..writeAsBytesSync(snapBytes());
    return collect(
      encodeContents(
        snapshot: f,
        snapshotBytes: 8192,
        settings: settings,
        manifest: manifest,
      ),
    );
  }

  Stream<List<int>> chunks(Uint8List b, [int size = 1000]) async* {
    for (var i = 0; i < b.length; i += size) {
      yield b.sublist(i, i + size > b.length ? b.length : i + size);
    }
  }

  test('round trip', () async {
    final out = File('${dir.path}/out.db');
    final d = await decodeContents(chunks(await valid()), out);
    expect(out.readAsBytesSync(), snapBytes());
    expect(d.settings, {'language': 'ar', 'digits': 'auto'});
    final m = SnapshotManifest.decode(d.manifestBytes);
    expect(m.tables, {'transactions': 3, 'settings': 2});
    expect(m.snapshotBytes, 8192);
  });

  test(
    'a plaintext SQLite snapshot is refused before a byte is written',
    () async {
      final v = await valid();
      final off = 1 + 'db.snapshot'.length + 8;
      v.setRange(off, off + 16, sqlitePlaintextMagic);
      final out = File('${dir.path}/out.db');
      await expectLater(decodeContents(chunks(v), out), corrupt);
      expect(out.existsSync() ? out.lengthSync() : 0, 0);
    },
  );

  test(
    'trailing byte, truncation, wrong name, wrong order, oversize',
    () async {
      final v = await valid();
      final out = File('${dir.path}/o.db');
      await expectLater(
        decodeContents(chunks(Uint8List.fromList([...v, 0])), out),
        corrupt,
      );
      await expectLater(
        decodeContents(chunks(v.sublist(0, v.length - 1)), out),
        corrupt,
      );
      final wrongName = Uint8List.fromList(v)..[1] = 'x'.codeUnitAt(0);
      await expectLater(decodeContents(chunks(wrongName), out), corrupt);
      final settingsFirst = Uint8List.fromList([
        ...header('settings.json', settings.length),
        ...settings,
      ]);
      await expectLater(decodeContents(chunks(settingsFirst), out), corrupt);
      final huge = header('db.snapshot', maxSnapshotBytes + 1);
      await expectLater(decodeContents(chunks(huge), out), corrupt);
      final negative = Uint8List.fromList(header('db.snapshot', 0))
        ..[1 + 11] = 0x80; // 2^63 → negative int
      await expectLater(decodeContents(chunks(negative), out), corrupt);
      final tiny = header('db.snapshot', 100);
      await expectLater(decodeContents(chunks(tiny), out), corrupt);
    },
  );

  test('manifest and settings decode strictly', () {
    expect(
      () => SnapshotManifest.decode(Uint8List.fromList('{}'.codeUnits)),
      throwsA(isA<BackupSnapshotException>()),
    );
    Uint8List j(String s) => Uint8List.fromList(s.codeUnits);
    const ok =
        '"v":1,"contentsVersion":1,"schemaVersion":4,"snapshotBytes":1,'
        '"settingsBytes":1,"tables":{"a":1}';
    expect(SnapshotManifest.decode(j('{$ok}')).tables, {'a': 1});
    expect(() => SnapshotManifest.decode(j('{$ok,"x":1}')), corrupt);
    expect(
      () => SnapshotManifest.decode(
        j('{${ok.replaceFirst('"a":1', '"a":1.5')}}'),
      ),
      corrupt,
    );
    expect(
      () => SnapshotManifest.decode(
        j('{${ok.replaceFirst('"a":1', '"A b":1')}}'),
      ),
      corrupt,
    );
    expect(() => decodeSettings(j('{"v":1,"settings":{"k":1}}')), corrupt);
    expect(
      () => decodeSettings(j('{"v":1,"settings":{"BAD KEY":"x"}}')),
      corrupt,
    );
    expect(() => decodeSettings(j('{"v":2,"settings":{}}')), corrupt);
    expect(decodeSettings(j('{"v":1,"settings":{"a.b":"x"}}')), {'a.b': 'x'});
  });
}
