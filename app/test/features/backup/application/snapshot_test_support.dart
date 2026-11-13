// T-149: two synthetic "phones" (A = backup source, B = restore target, each
// with its own K_db), a populated v4 database on A, dumps for the checklist,
// a crafting helper for hostile but authenticated backups, and a privacy
// scanner. Every row, sentinel and key is synthetic; keys are never printed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;
import 'package:zaghlol/features/backup/application/backup_contents.dart';
import 'package:zaghlol/features/backup/application/backup_snapshot_service.dart';
import 'package:zaghlol/features/backup/application/snapshot_db.dart';
import 'package:zaghlol/features/backup/crypto/backup_cipher.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/data/secure_state_key_slot_store.dart';

import '../../../core/db/db_open_harness.dart';
import '../../../core/db/financial_b_constraints_test.dart' as fb show validRow;
import '../../../core/db/financial_c_constraints_test.dart'
    as fc
    show v4NewTables, variants;
import '../../../core/db/financial_fixtures.dart';
import '../../../core/db/financial_schema_constraints_test.dart'
    as fa
    show validRow;
import '../../../core/db/financial_b_constraints_test.dart' show insertSql;
import '../../../support/fake_secret_store.dart';
import '../crypto/backup_test_support.dart';

const String passphrase = 'باسورد تجريبي ٣٤٥';

/// Backed-up sentinels (must survive the restore, must never be seen in a
/// plaintext file) and device sentinels (must never leave their phone).
const String noteSentinel = 'ZGLNOTESENTINEL';
const String smsSentinel = 'ZGLSMSSENTINEL';
const String settingSentinel = 'ZGLSETTINGSENTINEL';
const String deviceASentinel = 'ZGLDEVICEASENTINEL';
const String deviceBSentinel = 'ZGLDEVICEBSENTINEL';

const int seedA = 61;
const int seedB = 62;

/// One phone: its DB world, its open database, its cipher.
final class Phone {
  Phone._(this.world, this.db, this.seed, this.store);

  static Future<Phone> create(int seed, String tag) async {
    final world = await DbWorld.create(FakeSecretStore(), tag: tag);
    await world.tempDir.create(recursive: true);
    final db = openedDb(await world.open(seed: seed));
    return Phone._(world, db, seed, SlotSecretStore());
  }

  final DbWorld world;
  final AppDatabase db;
  final int seed;
  final SlotSecretStore store;

  late final BackupCipher cipher = BackupCipher(
    secretStore: store,
    slotStore: SecureStateKeySlotStore(() async => db),
    normalizer: ArabicNfcFake(),
    kdf: kdf,
    clock: () => DateTime.utc(2026, 11, 13, 9),
    leaseTimeout: const Duration(milliseconds: 200),
  );
  final FastKdf kdf = FastKdf();

  Directory get workDir =>
      Directory('${world.tempDir.path}/$backupWorkDirName');

  BackupSnapshotService service({
    BackupIsolateRunner runner = inlineRunner,
    void Function(String step)? onStep,
    int swapPagesPerStep = -1,
    void Function()? onSwapStep,
  }) => BackupSnapshotService(
    cipher: cipher,
    files: world.files,
    tempDirectory: () async => world.tempDir,
    liveKey: () async => keyOf(seed),
    runner: runner,
    onStep: onStep,
    swapPagesPerStep: swapPagesPerStep,
    onSwapStep: onSwapStep,
  );

  Future<void> dispose() async {
    await db.close();
    await world.dispose();
  }
}

Future<void> _exec(GeneratedDatabase db, Iterable<String> statements) async {
  for (final s in statements) {
    await db.customStatement(s);
  }
}

/// Fills every FR-BAK-06 table and every device table of [db] (phone A).
Future<void> populateSource(AppDatabase db) async {
  await _exec(db, [
    'INSERT INTO categories (id, system_code, name_ar, name_en, icon, color, '
        "bucket, sort) VALUES ('sys:food', 'food', 'أكل', 'Food', 'food', "
        "'#0F7A55', 'needs', 1)",
    insertSql('categories', {
      ...fa.validRow('categories', 'cust1'),
      'is_custom': '1',
      'parent_id': "'sys:food'",
    }),
    'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
        "VALUES (1, 'Synthetic One', 'groceries', 1)",
    'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
        "currency, cadence, created_at) VALUES ('ri1', 'bill', 'active', "
        "'Synthetic bill', 100, 'EGP', 'monthly', $t0)",
    'INSERT INTO assets (id, type, name, currency, manual_value_minor, '
        "created_at) VALUES ('a1', 'cash', 'Synthetic cash', 'EGP', 5000, "
        '$t0)',
  ]);
  await db.into(db.accounts).insert(account('acc1'));
  await db.into(db.rawMessages).insert(rawMessage('m1', hash: 1));
  await db.customStatement(
    'INSERT INTO raw_messages (id, channel, body, body_hash, received_at, '
    "parse_status, registry_version, created_at) VALUES ('m2', 'sms', "
    "'debit $smsSentinel 1,250.00 EGP', '${hashOf(2)}', $t0, 'parsed', 1, $t0)",
  );
  await db.into(db.transactions).insert(txn('e1', note: noteSentinel));
  await db.into(db.transactions).insert(txn('i1', direction: 'income'));
  await _exec(db, [
    insertSql('account_balances', fa.validRow('account_balances', 'usd1')),
    insertSql('transfer_pairs', fa.validRow('transfer_pairs', 'tp1')),
    insertSql('split_participants', fa.validRow('split_participants', 'sp1')),
    insertSql('offset_links', fa.validRow('offset_links', 'ol1')),
    for (final t in [
      'catalog_aliases',
      'catalog_keywords',
      'merchant_rules',
      'budgets',
      'fired_alerts',
      'cycle_summaries',
      'recurring_occurrences',
    ])
      insertSql(t, fb.validRow(t, 1)),
    for (final t in fc.v4NewTables)
      for (final v in fc.variants(t, 1)) insertSql(t, v),
    'INSERT INTO catalog_meta (id, version, applied_at, signature_kid) '
        "VALUES (1, 7, $t0, 'kid-a')",
    "INSERT INTO settings (key, value, updated_at) VALUES ('language', "
        "'ar', $t0)",
    "INSERT INTO settings (key, value, updated_at) VALUES ('test.sentinel', "
        "'$settingSentinel', $t0)",
    "INSERT INTO secure_state (key, value, updated_at) VALUES ('install_id', "
        "CAST('$deviceASentinel' AS BLOB), $t0)",
    "INSERT INTO db_meta (key, value) VALUES ('device', '$deviceASentinel')",
    "INSERT INTO diag_log (at, level, code) VALUES ($t0, 'info', "
        "'${deviceASentinel}_X')",
  ]);
}

/// Device rows of phone B (must survive a restore onto B).
Future<void> populateTarget(AppDatabase db) => _exec(db, [
  "INSERT INTO secure_state (key, value, updated_at) VALUES ('install_id', "
      "CAST('$deviceBSentinel' AS BLOB), $t0)",
  "INSERT INTO db_meta (key, value) VALUES ('device', '$deviceBSentinel')",
  'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
      "VALUES (5, 'Device B Merchant', 'groceries', 9)",
  'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
      "VALUES (5, 'device b alias', 'exact')",
  'INSERT INTO catalog_meta (id, version, applied_at, signature_kid) '
      "VALUES (1, 9, $t0, 'kid-b')",
  'INSERT INTO outbox (id, kind, payload, created_at) VALUES '
      "('obB', 'purchase_verify', '{\"t\":\"x\"}', $t0)",
  'INSERT INTO accounts (id, kind, label, default_currency, created_at, '
      "updated_at) VALUES ('accB', 'debit', 'B only', 'EGP', $t0, $t0)",
]);

String _cell(Object? v) => switch (v) {
  null => 'null',
  final Uint8List b => 'x${b.map((e) => e.toRadixString(16)).join()}',
  _ => '${v.runtimeType}:$v',
};

/// Every row of [tables], canonical and sorted (order-independent).
Future<Map<String, List<String>>> dump(
  GeneratedDatabase db,
  Iterable<String> tables,
) async => {
  for (final t in tables)
    t: [
      for (final r in await db.customSelect('SELECT * FROM "$t"').get())
        jsonEncode({for (final e in r.data.entries) e.key: _cell(e.value)}),
    ]..sort(),
};

/// Every non-virtual table of [db].
Future<List<String>> allTables(GeneratedDatabase db) async => [
  for (final r
      in await db
          .customSelect(
            "SELECT name FROM sqlite_schema WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL%'",
          )
          .get())
    r.read<String>('name'),
];

/// A full dump of the whole database (proof that nothing changed).
Future<Map<String, List<String>>> fullDump(GeneratedDatabase db) async =>
    dump(db, await allTables(db));

/// Opens [file] raw with [key].
sql.Database openRaw(File file, DbKeyMaterial key) {
  final raw = sql.sqlite3.open(file.path);
  applyEncryptedOpenSequence(raw, key);
  return raw;
}

/// Collects a byte stream.
Future<Uint8List> collectBytes(Stream<List<int>> s) async {
  final b = BytesBuilder(copy: false);
  await for (final e in s) {
    b.add(e);
  }
  return b.takeBytes();
}

/// Builds an authenticated (correctly encrypted under [keys]) backup whose
/// contents are shaped by the hooks: a hostile-but-genuine file, as only the
/// passphrase holder could make. [snapshot] overrides the snapshot source
/// (else A's live DB through [buildSnapshot]).
Future<Uint8List> craftBackup(
  Phone a,
  BackupKeys keys, {
  Future<void> Function(File snap, DbKeyMaterial kSnap)? prepareSnapshot,
  void Function(sql.Database snap)? mutate,
  Uint8List Function(Uint8List snapshotBytes)? rawSnapshot,
  SnapshotManifest Function(SnapshotManifest m)? editManifest,
  int headerSchema = appSchemaVersion,
}) async {
  final fileId = a.cipher.newFileId();
  final s = await keys.snapshotKey(fileId);
  final kSnap = DbKeyMaterial.copyOf(s.bytes);
  s.zeroize();
  final dir = await Directory.systemTemp.createTemp('zaghlol_t149_craft_');
  try {
    final snap = File('${dir.path}/craft.db');
    if (prepareSnapshot != null) {
      await prepareSnapshot(snap, kSnap);
    } else {
      await buildSnapshot(
        live: a.world.mainFile,
        liveKey: keyOf(a.seed),
        out: snap,
        snapKey: kSnap,
      );
    }
    final raw = openRaw(snap, kSnap);
    final Map<String, int> tables;
    final Map<String, String> settings;
    try {
      raw.execute('PRAGMA journal_mode = DELETE');
      mutate?.call(raw);
      tables = {
        for (final r in raw.select(
          "SELECT name FROM sqlite_schema WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL%'",
        ))
          r.columnAt(0) as String:
              raw
                      .select('SELECT count(*) FROM "${r.columnAt(0)}"')
                      .first
                      .columnAt(0)
                  as int,
      };
      settings = tables.containsKey('settings')
          ? {
              for (final r in raw.select('SELECT key, value FROM settings'))
                r.columnAt(0) as String: r.columnAt(1) as String,
            }
          : {};
    } finally {
      raw.close();
    }
    var bytes = await snap.readAsBytes();
    if (rawSnapshot != null) bytes = rawSnapshot(bytes);
    final body = File('${dir.path}/body.db');
    await body.writeAsBytes(bytes);
    final settingsBytes = encodeSettings(settings);
    var manifest = SnapshotManifest(
      contentsVersion: contentsVersionV1,
      schemaVersion: headerSchema,
      snapshotBytes: bytes.length,
      settingsBytes: settingsBytes.length,
      tables: tables,
    );
    if (editManifest != null) manifest = editManifest(manifest);
    return await collectBytes(
      a.cipher.encrypt(
        keys,
        HeaderMeta(
          seq: 1,
          schemaVersion: headerSchema,
          platform: BackupPlatform.android,
          appVersion: '0.1.0+1',
        ),
        encodeContents(
          snapshot: body,
          snapshotBytes: bytes.length,
          settings: settingsBytes,
          manifest: manifest.encode(),
        ),
        chunkSize: minChunkSize,
        fileId: fileId,
      ),
    );
  } finally {
    kSnap.zeroize();
    await dir.delete(recursive: true);
  }
}

/// Plaintext needles: any of them in a file on disk is a leak.
final List<List<int>> leakNeedles = [
  for (final s in [noteSentinel, smsSentinel, settingSentinel]) utf8.encode(s),
  sqlitePlaintextMagic,
];

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

bool containsBytes(List<int> hay, List<int> needle) => _contains(hay, needle);

/// Every file under [roots] that holds a plaintext needle (path relative
/// names only).
List<String> plaintextLeaks(List<Directory> roots) {
  final hits = <String>[];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      final List<int> bytes;
      try {
        bytes = f.readAsBytesSync();
      } on FileSystemException {
        continue; // deleted while listing
      }
      for (final n in leakNeedles) {
        if (_contains(bytes, n)) {
          hits.add(f.path.substring(root.path.length));
          break;
        }
      }
    }
  }
  return hits;
}

/// [dump] for a raw connection (same canonical form).
Map<String, List<String>> rawDump(sql.Database raw, Iterable<String> tables) =>
    {
      for (final t in tables)
        t: [
          for (final r in raw.select('SELECT * FROM "$t"'))
            jsonEncode({for (final e in r.entries) e.key: _cell(e.value)}),
        ]..sort(),
    };
