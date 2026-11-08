// T-007 (SPK-05): the encrypted-SQLite contract, shared by the host test
// (sqlite3mc_contract_test.dart) and the on-device test
// (integration_test/db_platform_test.dart). Nothing here is imported from
// lib/; it never ships.
//
// Hygiene rules (design note, "Key hygiene"):
// - Keys come only from Random.secure() and are never printed, never used in
//   a test name or `reason:`, and never written anywhere except the CI interop
//   file of the host job.
// - All data is synthetic. Sentinels and row text are never printed: every
//   database call goes through [guarded], which drops the original exception
//   (the sqlite3 package's message can include the statement and its bound
//   parameters) and keeps only the SQLite result code and, for statements
//   that carry no secret, SQLite's own error message.
// - Assertions compare booleans or counts, never sentinel strings, so a
//   failing `expect` cannot echo data into the CI log.
//
// The raw-SQL schema below is temporary: when T-015/T-016 create the Drift
// AppDatabase, these checks move onto it and the DDL here is deleted.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show GeneratedDatabase, QueryExecutor, Table, TableInfo, Variable;
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// SQLITE_NOTADB: "file is not a database".
const int sqliteNotADb = 26;

/// The `transactions_fts` DDL exactly as written in
/// docs/03-technical/database-schema.md §2.2 (the host test checks that).
const String transactionsFtsDdl =
    '''CREATE VIRTUAL TABLE transactions_fts USING fts5(      -- FR-TXN-01 search < 200 ms @ 50k
  merchant, counterparty, note, amount_text,
  content='transactions_fts_src', tokenize='trigram remove_diacritics 1'
);''';

/// Temporary external-content table and sync triggers (database-schema.md
/// keeps `transactions_fts` in sync with `transactions`; here a small source
/// table stands in until T-015/T-016).
const List<String> ftsSourceDdl = [
  '''CREATE TABLE transactions_fts_src (
  id INTEGER PRIMARY KEY,
  occurred_at INTEGER NOT NULL,
  merchant TEXT NOT NULL,
  counterparty TEXT NOT NULL,
  note TEXT NOT NULL,
  amount_text TEXT NOT NULL
)''',
  'CREATE INDEX ix_fts_src_occurred ON transactions_fts_src(occurred_at)',
  transactionsFtsDdl,
  '''CREATE TRIGGER transactions_fts_src_ai AFTER INSERT ON transactions_fts_src BEGIN
  INSERT INTO transactions_fts(rowid, merchant, counterparty, note, amount_text)
  VALUES (new.id, new.merchant, new.counterparty, new.note, new.amount_text);
END''',
  '''CREATE TRIGGER transactions_fts_src_ad AFTER DELETE ON transactions_fts_src BEGIN
  INSERT INTO transactions_fts(transactions_fts, rowid, merchant, counterparty, note, amount_text)
  VALUES ('delete', old.id, old.merchant, old.counterparty, old.note, old.amount_text);
END''',
  '''CREATE TRIGGER transactions_fts_src_au AFTER UPDATE ON transactions_fts_src BEGIN
  INSERT INTO transactions_fts(transactions_fts, rowid, merchant, counterparty, note, amount_text)
  VALUES ('delete', old.id, old.merchant, old.counterparty, old.note, old.amount_text);
  INSERT INTO transactions_fts(rowid, merchant, counterparty, note, amount_text)
  VALUES (new.id, new.merchant, new.counterparty, new.note, new.amount_text);
END''',
];

const String _insertSrc =
    'INSERT INTO transactions_fts_src '
    '(id, occurred_at, merchant, counterparty, note, amount_text) '
    'VALUES (?, ?, ?, ?, ?, ?)';

final RegExp _hexKey = RegExp(r'^[0-9a-f]{64}$');

/// A sanitized database failure: a stage name, the SQLite result code and
/// (only for statements without secrets) SQLite's error message. It never
/// carries SQL text, bound parameters, keys or row data.
final class DbContractException implements Exception {
  DbContractException(this.stage, {this.sqliteCode, this.detail});

  final String stage;
  final int? sqliteCode;
  final String? detail;

  @override
  String toString() =>
      'DbContractException($stage, sqlite=$sqliteCode'
      '${detail == null ? '' : ', $detail'})';
}

/// 32 bytes from [Random.secure], lowercase hex. Never print the result.
String randomHexKey() {
  final rng = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < 32; i++) {
    buf.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  final key = buf.toString();
  if (!_hexKey.hasMatch(key)) {
    throw DbContractException('key_format');
  }
  return key;
}

String _randomHex(int bytes) {
  final rng = Random.secure();
  return List<String>.generate(
    bytes,
    (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Synthetic sentinels: an ASCII one (`ZGHL-` + 16 random hex) and an Arabic
/// one with Arabic-Indic digits. Their UTF-8 bytes must never appear in an
/// encrypted file.
final class Sentinels {
  Sentinels._(this.latin, this.arabic);

  factory Sentinels.random() {
    final hex = _randomHex(8);
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    final rng = Random.secure();
    final digits = List<String>.generate(
      10,
      (_) => arabicDigits[rng.nextInt(10)],
    ).join();
    return Sentinels._('ZGHL-$hex', 'حارس زغلول $digits');
  }

  final String latin;
  final String arabic;

  List<List<int>> get utf8Needles => [utf8.encode(latin), utf8.encode(arabic)];
}

/// Finds the SQLite result code in [error] or in a wrapper's `cause` /
/// `remoteCause` (drift may wrap errors, especially across isolates).
int? sqliteCodeOf(Object error) {
  Object? current = error;
  for (var depth = 0; depth < 5 && current != null; depth++) {
    if (current is sql.SqliteException) return current.resultCode;
    if (current is DbContractException) return current.sqliteCode;
    current = _innerCause(current);
  }
  return null;
}

Object? _innerCause(Object error) {
  final dynamic d = error;
  for (final read in <Object? Function()>[
    () => d.cause as Object?,
    () => d.remoteCause as Object?,
  ]) {
    try {
      final inner = read();
      if (inner != null) return inner;
    } on NoSuchMethodError {
      // Not a wrapper with that field.
    }
  }
  return null;
}

void _rawExec(sql.Database raw, String statement, String stage) {
  try {
    raw.execute(statement);
  } on sql.SqliteException catch (e) {
    throw DbContractException(stage, sqliteCode: e.resultCode, detail: e.message);
  }
}

/// For statements that carry a key: the error keeps only the result code.
void _rawExecSecret(sql.Database raw, String statement, String stage) {
  try {
    raw.execute(statement);
  } on sql.SqliteException catch (e) {
    throw DbContractException(stage, sqliteCode: e.resultCode);
  }
}

List<List<Object?>> _rawSelect(sql.Database raw, String query, String stage) {
  try {
    return raw.select(query).rows;
  } on sql.SqliteException catch (e) {
    throw DbContractException(stage, sqliteCode: e.resultCode, detail: e.message);
  }
}

/// How a test database is keyed.
sealed class DbKey {
  const DbKey();
}

/// Raw 256-bit key: `PRAGMA key = "x'<64 hex>'"` (no PBKDF2 at open).
final class RawKey extends DbKey {
  RawKey(this.hex) {
    if (!_hexKey.hasMatch(hex)) throw DbContractException('key_format');
  }
  final String hex;
}

/// Passphrase key (SQLCipher 4 PBKDF2-HMAC-SHA512, 256,000 iterations).
/// Benchmark baseline only; the app uses [RawKey].
final class PassphraseKey extends DbKey {
  PassphraseKey(this.passphrase) {
    if (!RegExp(r'^[0-9a-f]{16,128}$').hasMatch(passphrase)) {
      throw DbContractException('passphrase_format');
    }
  }
  final String passphrase;
}

/// No key at all (plaintext baseline, or "open without the key").
final class NoKey extends DbKey {
  const NoKey();
}

/// The open sequence T-015 inherits (design note "Open sequence"). Runs in
/// drift's `setup`, before any other statement. Everything before the key is
/// a PRAGMA, because since SQLite 3.48 any SELECT reads the file.
///
/// With [verify], refuses to return unless the main database really is
/// SQLCipher-encrypted (throws `DB_NOT_ENCRYPTED`).
void applyOpenSequence(
  sql.Database raw, {
  required DbKey key,
  bool verify = true,
}) {
  _rawExec(raw, "PRAGMA cipher = 'sqlcipher'", 'pragma_cipher');
  _rawExec(raw, 'PRAGMA legacy = 4', 'pragma_legacy');
  switch (key) {
    case RawKey(:final hex):
      _rawExecSecret(raw, 'PRAGMA key = "x\'$hex\'"', 'pragma_key');
    case PassphraseKey(:final passphrase):
      _rawExecSecret(raw, "PRAGMA key = '$passphrase'", 'pragma_key');
    case NoKey():
      break;
  }
  _rawExec(raw, 'PRAGMA temp_store = 2', 'pragma_temp_store');
  _rawExec(raw, 'PRAGMA journal_mode = WAL', 'pragma_journal_mode');
  _rawExec(raw, 'PRAGMA synchronous = NORMAL', 'pragma_synchronous');
  if (verify) verifyEncrypted(raw);
}

/// The verification half of the open sequence.
void verifyEncrypted(sql.Database raw) {
  // Forces decryption of page 1.
  _rawSelect(raw, 'SELECT count(*) FROM sqlite_master', 'verify_master');
  final cipher = _rawSelect(raw, 'PRAGMA cipher', 'verify_cipher');
  if (cipher.isEmpty || cipher.first.first != 'sqlcipher') {
    throw DbContractException('DB_NOT_ENCRYPTED', detail: 'cipher');
  }
  final salt = _rawSelect(
    raw,
    "SELECT sqlite3mc_codec_data('cipher_salt')",
    'verify_salt',
  );
  if (salt.isEmpty || salt.first.first == null) {
    throw DbContractException('DB_NOT_ENCRYPTED', detail: 'salt');
  }
}

/// Minimal drift database without generated code: the real open path
/// (`NativeDatabase` / `createInBackground` + `setup`) with raw SQL on top.
class ContractDb extends GeneratedDatabase {
  ContractDb(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

// Built in its own function so the closure sent to the background isolate
// captures only the key and the flag.
void Function(sql.Database) _setupFor(DbKey key, bool verify) =>
    (raw) => applyOpenSequence(raw, key: key, verify: verify);

/// Opens [file] in this isolate (deterministic for the file-level checks).
ContractDb openForeground(File file, DbKey key, {bool verify = true}) {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return ContractDb(NativeDatabase(file, setup: _setupFor(key, verify)));
}

/// Opens [file] the way the app will: `NativeDatabase.createInBackground`.
ContractDb openBackground(File file, DbKey key, {bool verify = true}) {
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final QueryExecutor executor = NativeDatabase.createInBackground(
    file,
    setup: _setupFor(key, verify),
  );
  return ContractDb(executor);
}

/// Runs [body], replacing any failure with a sanitized [DbContractException].
Future<T> guarded<T>(String stage, Future<T> Function() body) async {
  try {
    return await body();
  } on DbContractException {
    rethrow;
  } catch (e) {
    String? detail;
    Object? current = e;
    for (var depth = 0; depth < 5 && current != null; depth++) {
      if (current is sql.SqliteException) {
        detail = current.message;
        break;
      }
      if (current is DbContractException) {
        detail = current.toString();
        break;
      }
      current = _innerCause(current);
    }
    throw DbContractException(
      stage,
      sqliteCode: sqliteCodeOf(e),
      detail: detail ?? e.runtimeType.toString(),
    );
  }
}

Future<List<List<Object?>>> query(
  ContractDb db,
  String sqlText, [
  List<Object?> args = const [],
  String stage = 'query',
]) => guarded(stage, () async {
  final rows = await db
      .customSelect(
        sqlText,
        variables: [for (final a in args) _variable(a)],
      )
      .get();
  return [for (final r in rows) r.data.values.toList()];
});

Future<Object?> scalar(
  ContractDb db,
  String sqlText, [
  List<Object?> args = const [],
  String stage = 'scalar',
]) async {
  final rows = await query(db, sqlText, args, stage);
  return rows.isEmpty || rows.first.isEmpty ? null : rows.first.first;
}

Future<void> statement(
  ContractDb db,
  String sqlText, [
  List<Object?> args = const [],
  String stage = 'statement',
]) => guarded(stage, () => db.customStatement(sqlText, args));

Variable<Object> _variable(Object? value) => switch (value) {
  final String s => Variable<String>(s),
  final int i => Variable<int>(i),
  _ => throw DbContractException('unsupported_variable'),
};

/// Opens [file] with [key] (no verification) and runs a read that needs page
/// 1. Returns null when that worked, else the SQLite result code (or -1 if the
/// failure carried none).
Future<int?> openFailureCode(File file, DbKey key) async {
  final db = openForeground(file, key, verify: false);
  try {
    await guarded(
      'probe_read',
      () => db.customSelect('SELECT count(*) FROM sqlite_master').get(),
    );
    return null;
  } on DbContractException catch (e) {
    return e.sqliteCode ?? -1;
  } finally {
    await db.close().catchError((Object _) {});
  }
}

/// Creates the sentinel table and the FTS schema and writes both sentinels to
/// each, inside one transaction.
Future<void> writeSentinels(ContractDb db, Sentinels s) async {
  await statement(
    db,
    'CREATE TABLE sentinels (id INTEGER PRIMARY KEY, latin TEXT, arabic TEXT)',
  );
  for (final ddl in ftsSourceDdl) {
    await statement(db, ddl, const [], 'fts_ddl');
  }
  await guarded(
    'write_sentinels',
    () => db.transaction(() async {
      await db.customStatement(
        'INSERT INTO sentinels (latin, arabic) VALUES (?, ?)',
        [s.latin, s.arabic],
      );
      await db.customStatement(_insertSrc, [
        1,
        1_790_000_000_000,
        s.latin,
        s.arabic,
        s.latin,
        s.arabic,
      ]);
    }),
  );
}

Future<int> sentinelCount(ContractDb db) async =>
    (await scalar(db, 'SELECT count(*) FROM sentinels')) as int;

/// The file plus its WAL and shared-memory companions.
List<File> dbFiles(File db) => [
  db,
  File('${db.path}-wal'),
  File('${db.path}-shm'),
];

/// Names of every entry in [dir].
Set<String> entryNames(Directory dir) => {
  for (final e in dir.listSync()) e.uri.pathSegments.lastWhere((p) => p != ''),
};

/// True if any existing file in [files] contains any needle.
bool anyFileContains(List<File> files, List<List<int>> needles) {
  for (final f in files) {
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    for (final n in needles) {
      if (indexOfBytes(bytes, n) >= 0) return true;
    }
  }
  return false;
}

int indexOfBytes(Uint8List hay, List<int> needle) {
  if (needle.isEmpty) return 0;
  final first = needle.first;
  final last = hay.length - needle.length;
  outer:
  for (var i = 0; i <= last; i++) {
    if (hay[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// `SQLite format 3\0`.
const List<int> sqliteMagic = [
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
];

bool hasPlaintextHeader(File f) {
  final raf = f.openSync();
  try {
    final head = raf.readSync(16);
    if (head.length < 16) return false;
    for (var i = 0; i < 16; i++) {
      if (head[i] != sqliteMagic[i]) return false;
    }
    return true;
  } finally {
    raf.closeSync();
  }
}

/// Library facts recorded in ADR-002 (no data).
final class LibraryInfo {
  LibraryInfo(this.sqliteVersion, this.mcVersion, this.compileOptions);
  final String sqliteVersion;
  final String? mcVersion;
  final List<String> compileOptions;

  bool get hasFts5 => compileOptions.contains('ENABLE_FTS5');

  bool atLeast(int major, int minor, int patch) {
    final parts = sqliteVersion.split('.').map(int.tryParse).toList();
    final v = [for (var i = 0; i < 3; i++) i < parts.length ? parts[i] ?? 0 : 0];
    if (v[0] != major) return v[0] > major;
    if (v[1] != minor) return v[1] > minor;
    return v[2] >= patch;
  }
}

Future<LibraryInfo> libraryInfo(ContractDb db) async {
  final version = (await scalar(db, 'SELECT sqlite_version()')) as String;
  String? mc;
  try {
    mc = (await scalar(db, 'SELECT sqlite3mc_version()')) as String?;
  } on DbContractException {
    mc = null; // upstream SQLite: no such function (negative proof a)
  }
  final options = [
    for (final r in await query(db, 'PRAGMA compile_options')) r.first as String,
  ];
  return LibraryInfo(version, mc, options);
}

/// FTS5 rows for the functional checks (synthetic). Row 3 carries tashkeel.
const List<(int, String, String, String, String)> _ftsFixture = [
  (101, 'Café Riche', 'Downtown Branch', 'synthetic lunch', '1,250.00 ١٬٢٥٠٫٠٠'),
  (102, 'هايبر كارفور المعادي', 'فرع المعادي', 'مشتريات البيت', '٣٤٠٫٥٠ 340.50'),
  (103, 'مُحَمَّد للعطور', 'محل العطور', 'هدية', '75.00 ٧٥٫٠٠'),
  (104, 'Kiosk Nile', 'Zamalek', 'كارت شحن', '20.00 ٢٠٫٠٠'),
];

Future<Set<int>> _matchIds(ContractDb db, String term) async {
  final rows = await query(
    db,
    'SELECT rowid FROM transactions_fts WHERE transactions_fts MATCH ?',
    [ftsQuote(term)],
    'fts_match',
  );
  return {for (final r in rows) r.first as int};
}

Future<Set<int>> _likeIds(ContractDb db, String pattern) async {
  final rows = await query(
    db,
    'SELECT rowid FROM transactions_fts WHERE merchant LIKE ?',
    [pattern],
    'fts_like',
  );
  return {for (final r in rows) r.first as int};
}

/// FTS5 string literal for a user term.
String ftsQuote(String term) => '"${term.replaceAll('"', '""')}"';

/// Inserts the FTS fixture. The schema must already exist.
Future<void> insertFtsFixture(ContractDb db) => guarded(
  'fts_fixture',
  () => db.transaction(() async {
    for (final (id, merchant, counterparty, note, amount) in _ftsFixture) {
      await db.customStatement(_insertSrc, [
        id,
        1_790_000_000_000 + id,
        merchant,
        counterparty,
        note,
        amount,
      ]);
    }
  }),
);

/// Recorded, not asserted (design note "FTS5 checks"), plus other facts the
/// ADR needs. No data: counts, booleans, result codes, the query-plan detail.
final Map<String, Object?> findings = {};

/// Prints the findings line once per run (only counts/flags/codes).
void emitFindings(String env) {
  // ignore: avoid_print
  print('ZAGHLOL_DB_FINDINGS ${jsonEncode({'env': env, ...findings})}');
}

/// Registers the contract on the current platform. [env] labels output lines.
void registerSqlite3mcContract({required String env}) {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t007_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  tearDownAll(() => emitFindings(env));

  group('sqlite3mc contract', () {
    test('library is SQLite3MultipleCiphers with FTS5 on SQLite >= 3.45', () async {
      final db = openForeground(File('${dir.path}/lib.db'), RawKey(randomHexKey()));
      try {
        final info = await libraryInfo(db);
        findings['sqlite_version'] = info.sqliteVersion;
        findings['sqlite3mc_version'] = info.mcVersion;
        findings['tmp_parent'] = dir.parent.path;
        expect(info.hasFts5, isTrue, reason: 'ENABLE_FTS5 in compile_options');
        expect(
          info.atLeast(3, 45, 0),
          isTrue,
          reason: 'trigram remove_diacritics needs SQLite 3.45.0',
        );
        expect(info.mcVersion, isNotNull, reason: 'sqlite3mc_version() exists');
      } finally {
        await db.close();
      }
    });

    test('the open sequence verifies cipher and salt (background isolate)', () async {
      final file = File('${dir.path}/verify.db');
      final key = RawKey(randomHexKey());
      final db = openBackground(file, key);
      try {
        expect(await scalar(db, 'SELECT count(*) FROM sqlite_master'), isA<int>());
        expect(await scalar(db, 'PRAGMA cipher') == 'sqlcipher', isTrue,
            reason: 'PRAGMA cipher returns sqlcipher');
        expect(
          await scalar(db, "SELECT sqlite3mc_codec_data('cipher_salt')"),
          isNotNull,
          reason: 'main database has a cipher salt',
        );
        expect(await scalar(db, 'PRAGMA journal_mode') == 'wal', isTrue,
            reason: 'journal_mode WAL');
        expect(await scalar(db, 'PRAGMA temp_store'), 2, reason: 'temp_store MEMORY');
      } finally {
        await db.close();
      }
    });

    test('no key and a wrong key are refused with SQLITE_NOTADB', () async {
      final file = File('${dir.path}/refuse.db');
      final s = Sentinels.random();
      final db = openForeground(file, RawKey(randomHexKey()), verify: false);
      await writeSentinels(db, s);
      await db.close();

      final noKey = await openFailureCode(file, const NoKey());
      final wrongKey = await openFailureCode(file, RawKey(randomHexKey()));
      findings['no_key_code'] = noKey;
      findings['wrong_key_code'] = wrongKey;
      expect(noKey, sqliteNotADb, reason: 'open without key');
      expect(wrongKey, sqliteNotADb, reason: 'open with a wrong key');
    });

    test('a plaintext file is refused when a key is applied', () async {
      final file = File('${dir.path}/plain.db');
      final s = Sentinels.random();
      final plain = openForeground(file, const NoKey(), verify: false);
      await writeSentinels(plain, s);
      await plain.close();

      // Positive controls: the header check and the byte scan do detect a
      // plaintext file made by the same library.
      expect(hasPlaintextHeader(file), isTrue, reason: 'control: plaintext header');
      expect(anyFileContains(dbFiles(file), s.utf8Needles), isTrue,
          reason: 'control: scanner finds plaintext sentinels');

      final keyed = await openFailureCode(file, RawKey(randomHexKey()));
      findings['plaintext_with_key_code'] = keyed;
      expect(keyed, sqliteNotADb, reason: 'key applied to a plaintext file');

      // And the full open sequence refuses it too (never opens as plaintext).
      final verified = openForeground(file, RawKey(randomHexKey()));
      Object? failure;
      try {
        await guarded('verify_plain', () => verified.customSelect('SELECT 1').get());
      } on DbContractException catch (e) {
        failure = e;
      } finally {
        await verified.close().catchError((Object _) {});
      }
      expect(failure, isA<DbContractException>(), reason: 'open sequence refuses plaintext');
    });

    test('header, -wal and -shm hold no plaintext (open and after close)', () async {
      final file = File('${dir.path}/scan.db');
      final s = Sentinels.random();
      final db = openForeground(file, RawKey(randomHexKey()), verify: false);
      try {
        // Keep the writes in the WAL while the connection is open.
        await statement(db, 'PRAGMA wal_autocheckpoint = 0');
        await writeSentinels(db, s);
        expect(await sentinelCount(db), 1);
        final wal = File('${file.path}-wal');
        expect(wal.existsSync() && wal.lengthSync() > 0, isTrue,
            reason: 'un-checkpointed WAL exists while open');
        expect(anyFileContains(dbFiles(file), s.utf8Needles), isFalse,
            reason: 'no sentinel bytes in db/-wal/-shm while open');
        expect(entryNames(dir).difference({'scan.db', 'scan.db-wal', 'scan.db-shm'}),
            isEmpty, reason: 'only db, -wal, -shm in the directory while open');
      } finally {
        await db.close();
      }
      expect(hasPlaintextHeader(file), isFalse, reason: 'header is not SQLite format 3');
      expect(anyFileContains(dbFiles(file), s.utf8Needles), isFalse,
          reason: 'no sentinel bytes after close');
      expect(entryNames(dir).difference({'scan.db', 'scan.db-wal', 'scan.db-shm'}),
          isEmpty, reason: 'only db, -wal, -shm in the directory after close');
    });

    test('rekey round-trip: K2 opens, K1 is refused', () async {
      final file = File('${dir.path}/rekey.db');
      final s = Sentinels.random();
      final k1 = RawKey(randomHexKey());
      final k2 = RawKey(randomHexKey());
      final db = openForeground(file, k1);
      await writeSentinels(db, s);
      // Record whether rekey works in WAL mode before falling back to the
      // documented path (rekey in rollback-journal mode).
      try {
        await guarded('rekey_wal', () => db.customStatement('PRAGMA rekey = "x\'${k2.hex}\'"'));
        findings['rekey_in_wal'] = 'ok';
      } on DbContractException catch (e) {
        findings['rekey_in_wal'] = 'error ${e.sqliteCode}';
        await statement(db, 'PRAGMA journal_mode = DELETE');
        await guarded('rekey_delete', () => db.customStatement('PRAGMA rekey = "x\'${k2.hex}\'"'));
        await statement(db, 'PRAGMA journal_mode = WAL');
      }
      await db.close();

      final reopened = openForeground(file, k2);
      try {
        expect(await sentinelCount(reopened), 1, reason: 'K2 opens and reads');
      } finally {
        await reopened.close();
      }
      expect(await openFailureCode(file, k1), sqliteNotADb, reason: 'K1 refused after rekey');
      expect(hasPlaintextHeader(file), isFalse, reason: 'still encrypted after rekey');
    });

    test('FTS5 trigram: DDL as written, Latin, Arabic, digits, LIKE via index', () async {
      final db = openForeground(File('${dir.path}/fts.db'), RawKey(randomHexKey()));
      try {
        for (final ddl in ftsSourceDdl) {
          await statement(db, ddl, const [], 'fts_ddl');
        }
        await insertFtsFixture(db);

        expect(await _matchIds(db, 'cafe'), contains(101), reason: 'Café ~ cafe');
        expect(await _matchIds(db, 'CAFÉ'), contains(101), reason: 'case-insensitive');
        expect(await _matchIds(db, 'كارفور'), {102}, reason: 'Arabic substring');
        expect(await _matchIds(db, '1,250'), {101}, reason: 'Latin digits');
        expect(await _matchIds(db, '١٬٢٥٠'), {101}, reason: 'Arabic-Indic digits');
        expect(await _matchIds(db, '340.5'), {102}, reason: 'Latin digits, Arabic row');

        expect(await _likeIds(db, '%RICHE%'), {101}, reason: 'LIKE substring');
        final plan = [
          for (final r in await query(
            db,
            'EXPLAIN QUERY PLAN SELECT rowid FROM transactions_fts WHERE merchant LIKE ?',
            ['%riche%'],
            'fts_plan',
          ))
            r.last.toString(),
        ].join(' | ');
        findings['like_plan'] = plan;
        expect(RegExp(r'VIRTUAL TABLE INDEX \d+:\S*L').hasMatch(plan), isTrue,
            reason: 'LIKE is served by the trigram index');

        // Recorded only.
        findings['tashkeel_folded'] = (await _matchIds(db, 'محمد')).contains(103);
        findings['match_1ch_rows'] = (await _matchIds(db, 'ك')).length;
        findings['match_2ch_rows'] = (await _matchIds(db, 'كا')).length;
        findings['like_2ch_rows'] = (await _likeIds(db, '%كا%')).length;
        findings['latin_diacritics_folded'] = (await _matchIds(db, 'cafe')).contains(101);
      } finally {
        await db.close();
      }
    });
  });
}
