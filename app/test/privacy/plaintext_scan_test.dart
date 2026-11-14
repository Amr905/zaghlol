// T-171 checks 1 and 3 (testing-strategy §1 "Privacy"; FR-SEC-03,
// FR-CAP-02, BR-CAP-01), host part: after a scripted session on the app's
// encrypted database (SMS ingestion with an amount, card digits, a merchant
// and message text; a note; a setting; device state), no file the app wrote
// holds any of it in plaintext - main DB, WAL, SHM, journal, temp - while
// the database is open and after it closed. An ignored-card SMS leaves no
// trace in any table (FTS shadow tables included) or diagnostic.
//
// Covered elsewhere (and listed in the task file's AC map): native spools,
// capture status, share store, widget snapshot and Guard config (Kotlin
// and Swift unit tests), backup files at every step (T-149
// backup_restore_test "AC2 privacy"). The on-phone sandbox scan of a
// release candidate is the manual procedure in the task file.
//
// Every message and value is synthetic.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/features/share_cards/application/share_providers.dart';

import '../features/ingestion/support/ingest_harness.dart';

/// Kept on the phone (encrypted only).
const Map<String, String> kept = {
  'amount': '7391.42',
  'merchant': 'zglcanary mart',
  'card': '8642',
  'smsText': 'ZGLSMSCANARY',
  'note': 'ZGLNOTECANARY',
  'setting': 'ZGLSETTINGCANARY',
  'device': 'ZGLDEVICECANARY',
};

/// From an ignored card: must leave no trace at all (FR-CAP-02).
const Map<String, String> ignored = {
  'amount': '6283.17',
  'merchant': 'zglignored shop',
  'card': '9753',
};

/// `SQLite format 3\0`: an unencrypted database page 1.
final List<int> sqliteMagic = [...ascii.encode('SQLite format 3'), 0];

List<List<int>> needlesOf(Iterable<String> values) => [
  for (final v in values) ...[
    utf8.encode(v),
    utf8.encode(v.toUpperCase()),
    // UTF-16LE, as some platform stores write text.
    [
      for (final c in v.codeUnits) ...[c & 0xff, c >> 8],
    ],
  ],
];

bool containsBytes(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Relative paths of files under [root] holding any needle.
List<String> leaks(Directory root, List<List<int>> needles) {
  final hits = <String>[];
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    final Uint8List bytes;
    try {
      bytes = f.readAsBytesSync();
    } on FileSystemException {
      continue;
    }
    if (needles.any((n) => containsBytes(bytes, n))) {
      hits.add(f.path.substring(root.path.length));
    }
  }
  return hits;
}

void main() {
  late IngestWorld w;
  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  /// Every value of every table except [skip], lower-cased.
  Future<String> everyRow({Set<String> skip = const {}}) async {
    final tables = await w.rows(
      "SELECT name FROM sqlite_schema WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    final b = StringBuffer();
    for (final t in tables) {
      final name = t['name']! as String;
      if (skip.contains(name)) continue;
      for (final r in await w.rows('SELECT * FROM "$name"')) {
        for (final v in r.values) {
          b.write(v is Uint8List ? utf8.decode(v, allowMalformed: true) : v);
          b.write('|');
        }
      }
    }
    return b.toString().toLowerCase();
  }

  Future<void> session() async {
    await CaptureControlsDao(w.db).addIgnoreRule(
      id: 'ig1',
      institutionCode: 'zbank',
      last4: ignored['card'],
      channel: 'sms',
      createdAt: t0,
    );
    final r = await w.run([
      sms(
        'k1',
        'ZBANK: Purchase EGP ${kept['amount']} at Zglcanary Mart '
            'card *${kept['card']}',
      ),
      sms('k2', 'ZBANK: notice ${kept['smsText']} EGP 5'),
      sms(
        'x1',
        'ZBANK: Purchase EGP ${ignored['amount']} at Zglignored Shop '
            'card *${ignored['card']}',
      ),
    ]);
    expect(r.outcomes['k1'], isA<IngestInserted>());
    expect((r.outcomes['x1']! as IngestDropped).reason, 'ignored_card');
    await w.db.customStatement('UPDATE transactions SET note = ?1', [
      kept['note'],
    ]);
    await w.db.customStatement(
      'INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)',
      ['t171.canary', kept['setting'], t0],
    );
    await w.db.customStatement(
      'INSERT INTO secure_state (key, value, updated_at) VALUES (?1, ?2, ?3)',
      ['t171.canary', utf8.encode(kept['device']!), t0],
    );
  }

  test('FR-SEC-03: no plaintext amount, card digits, merchant, message, '
      'note, setting or device state in any file, with the database open '
      '(WAL) and after close', () async {
    await session();
    // Sanity: the scan reads real data (the canaries are in the database).
    final rows = await everyRow();
    for (final v in kept.values) {
      expect(rows, contains(v.toLowerCase()), reason: v);
    }

    final root = w.edb.world.root;
    final needles = [
      ...needlesOf([...kept.values, ...ignored.values]),
      sqliteMagic,
    ];
    final files = root.listSync(recursive: true).whereType<File>().toList();
    expect(files.map((f) => f.path), contains(w.edb.world.mainFile.path));
    expect(leaks(root, needles), isEmpty, reason: 'open');

    await w.db.close();
    expect(leaks(root, needles), isEmpty, reason: 'closed');
  });

  test('FR-CAP-02: an ignored-card SMS leaves no trace in any table (FTS '
      'shadow tables included) or diagnostic', () async {
    await session();
    // The user's own ignore rule holds the card digits by design.
    final rows = await everyRow(skip: {'ignore_rules'});
    expect(rows, contains(kept['merchant'])); // the scan sees real rows
    for (final e in ignored.entries) {
      expect(rows, isNot(contains(e.value)), reason: e.key);
    }
    expect(w.diag.counts.keys, isNot(contains(contains('9753'))));
    for (final e in w.events) {
      expect('$e', isNot(contains(ignored['merchant'])));
    }
  });

  test('the share staging file is gone after the share, also when the '
      'share sheet fails', () async {
    final dir = await Directory.systemTemp.createTemp('zaghlol_t171_share_');
    addTearDown(() => dir.delete(recursive: true));
    final ok = StagedShareSheet(invoke: (_) async {}, dir: () async => dir);
    await ok.sharePng(Uint8List.fromList([1, 2, 3]));
    expect(dir.listSync(), isEmpty);
    final failing = StagedShareSheet(
      invoke: (_) async => throw StateError('share sheet down'),
      dir: () async => dir,
    );
    await expectLater(
      failing.sharePng(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
    expect(dir.listSync(), isEmpty);
  });

  test('negative proof: the file scan finds a planted plaintext canary and '
      'an unencrypted SQLite file', () {
    final root = Directory.systemTemp.createTempSync('zaghlol_t171_neg_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/a.bin')
        .writeAsBytesSync([9, ...utf8.encode('x ${kept['merchant']} y')]);
    File('${root.path}/b.db').writeAsBytesSync([...sqliteMagic, 1, 2]);
    File('${root.path}/c.bin').writeAsBytesSync(needlesOf(['7391.42'])[2]);
    expect(
      leaks(root, [
        ...needlesOf(kept.values),
        sqliteMagic,
      ]).map((p) => p.substring(1)).toSet(),
      {'a.bin', 'b.db', 'c.bin'},
    );
  });
}
