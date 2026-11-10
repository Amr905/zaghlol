// T-007 (SPK-05): the 50k-row FTS benchmark, shared by the host benchmark
// test and the on-device test. Deterministic synthetic data (Random(7)); the
// output line carries numbers, environment and versions only: no data, no key.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sqlite3mc_contract.dart';

const int benchRows = 50000;

const List<String> _arPrefixes = [
  'هايبر', 'سوبر ماركت', 'صيدلية', 'مطعم', 'كافيه', //
  'مخبز', 'محطة', 'مكتبة', 'معرض', 'عيادة',
];
const List<String> _arNames = [
  'كارفور', 'النيل', 'العزبي', 'الشروق', 'الهرم', //
  'الزمالك', 'المعادي', 'فتح الله', 'أبو عوف', 'زهران',
  'الرحاب', 'التحرير', 'الأهرام', 'الدقي', 'المهندسين',
];
const List<String> _enPrefixes = [
  'Café', 'Market', 'Pharmacy', 'Bakery', 'Station', //
  'Store', 'Clinic', 'Garage', 'Studio', 'Kiosk',
];
const List<String> _enNames = [
  'Nile', 'Delta', 'Giza', 'Zamalek', 'Maadi', //
  'Heliopolis', 'Dokki', 'Rehab', 'Sheikh Zayed', 'Tagamoa',
  'Mohandessin', 'Shorouk', 'Obour', 'Nasr City', 'Garden City',
];
const List<String> _notes = [
  'مشتريات البيت', 'عشاء مع العيلة', 'تحويل لأحمد', 'فاتورة الكهربا', //
  'groceries', 'dinner', 'fuel', 'school supplies', 'هدية عيد ميلاد', '',
];

/// About 300 synthetic merchant names (150 Arabic, 150 Latin).
final List<String> benchNames = [
  for (final p in _arPrefixes)
    for (final n in _arNames) '$p $n',
  for (final p in _enPrefixes)
    for (final n in _enNames) '$p $n',
];

/// 20 search terms (3+ characters): Arabic, Latin, digits in both systems.
const List<String> benchTerms = [
  'كارفور', 'صيدلية', 'الزمالك', 'مطعم', 'المعادي', //
  'سوبر', 'تحويل', 'عشاء', 'Market', 'Pharm',
  'Nile', 'Zamalek', 'cafe', 'Heliop', 'Dokki',
  'Bakery', '1,2', '٢٥٠', '500', '٫٥٠',
];

/// 2-character fallback queries (trigram cannot serve them).
const List<String> benchShortTerms = ['كا', 'Ca', '١٢', 'ma', 'صي'];

const String _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// `1,250.00` from integer minor units (exponent 2). No doubles.
String latinAmount(int minor) {
  final major = (minor ~/ 100).toString();
  final frac = (minor % 100).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < major.length; i++) {
    if (i > 0 && (major.length - i) % 3 == 0) grouped.write(',');
    grouped.write(major[i]);
  }
  return '$grouped.$frac';
}

/// `١٬٢٥٠٫٠٠` (Arabic-Indic digits, Arabic separators).
String arabicAmount(int minor) {
  final buf = StringBuffer();
  for (final ch in latinAmount(minor).split('')) {
    final d = int.tryParse(ch);
    buf.write(
      d != null
          ? _arabicDigits[d]
          : ch == ','
          ? '٬'
          : '٫',
    );
  }
  return buf.toString();
}

/// Deterministic rows: (id, occurred_at, merchant, counterparty, note, amount_text).
List<List<Object?>> benchData() {
  final rng = Random(7);
  const base = 1790000000000; // fixed epoch ms
  const twoYearsSeconds = 2 * 365 * 24 * 3600;
  final rows = <List<Object?>>[];
  for (var i = 1; i <= benchRows; i++) {
    final minor = 100 + rng.nextInt(5000000);
    final occurredAt = base - rng.nextInt(twoYearsSeconds) * 1000;
    final merchant = benchNames[rng.nextInt(benchNames.length)];
    final counterparty = rng.nextInt(4) == 0
        ? benchNames[rng.nextInt(benchNames.length)]
        : '';
    final note = _notes[rng.nextInt(_notes.length)];
    rows.add([
      i,
      occurredAt,
      merchant,
      counterparty,
      note,
      '${latinAmount(minor)} ${arabicAmount(minor)}',
    ]);
  }
  return rows;
}

/// p50 / p95 / max in ms (nearest rank), one decimal.
List<double> percentiles(List<int> micros) {
  final s = [...micros]..sort();
  int at(double p) => s[max(0, (p * s.length).ceil() - 1)];
  return [_ms(at(0.50)), _ms(at(0.95)), _ms(s.last)];
}

double _ms(int micros) => (micros / 100).round() / 10;

Future<int> _timed(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

const String _rankQuery =
    'SELECT rowid FROM transactions_fts WHERE transactions_fts MATCH ? '
    'ORDER BY rank LIMIT 50';
const String _listQuery =
    'SELECT s.id, s.occurred_at, s.merchant, s.amount_text '
    'FROM transactions_fts f JOIN transactions_fts_src s ON s.id = f.rowid '
    'WHERE transactions_fts MATCH ? ORDER BY s.occurred_at DESC LIMIT 50';

/// T-016 §8(b): the short-query variant for T-017. A second, small FTS5 table
/// over merchant and counterparty only, with unicode61 word tokens and
/// 1- and 2-character prefix indexes, so 1–2 character queries become a
/// word-prefix MATCH ('ab*') instead of a LIKE scan.
const String shortPrefixDdl =
    'CREATE VIRTUAL TABLE transactions_fts_short USING fts5('
    'merchant, counterparty, '
    "tokenize='unicode61 remove_diacritics 2', prefix='1 2')";

const String _shortPrefixFill =
    'INSERT INTO transactions_fts_short (rowid, merchant, counterparty) '
    'SELECT id, merchant, counterparty FROM transactions_fts_src';

const String _shortPrefixQuery =
    'SELECT s.id FROM transactions_fts_short f '
    'JOIN transactions_fts_src s ON s.id = f.rowid '
    'WHERE transactions_fts_short MATCH ? '
    'ORDER BY s.occurred_at DESC LIMIT 50';

/// `"ab"*`: a quoted word-prefix query.
String ftsPrefix(String term) => '${ftsQuote(term)}*';

/// Measured passes per query set; each pass is preceded by one discarded
/// warm-up pass. Reported percentiles are the median over the passes.
const int benchPasses = 3;

/// The median of each percentile (p50, p95, max) over [passes].
List<double> medianOfPasses(List<List<double>> passes) {
  double median(List<double> xs) {
    final s = [...xs]..sort();
    return s[s.length ~/ 2];
  }

  return [
    for (var i = 0; i < 3; i++) median([for (final p in passes) p[i]]),
  ];
}

/// One warm-up pass, then [benchPasses] measured passes of [pass] (each
/// returns per-query micros); percentiles per pass, median across passes.
Future<List<double>> _measured(Future<List<int>> Function() pass) async {
  await pass(); // warm-up, discarded
  return medianOfPasses([
    for (var i = 0; i < benchPasses; i++) percentiles(await pass()),
  ]);
}

const String _shortQuery =
    'SELECT id FROM transactions_fts_src '
    'WHERE merchant LIKE ? OR counterparty LIKE ? OR note LIKE ? '
    'ORDER BY occurred_at DESC LIMIT 50';

/// One mode (encrypted with a raw key, or plaintext) end to end.
Future<Map<String, Object?>> _benchMode(Directory dir, DbKey key) async {
  final file = File('${dir.path}/bench_${key is NoKey ? 'plain' : 'enc'}.db');
  final data = benchData();
  // The plaintext baseline cannot pass the encryption check.
  final verify = key is! NoKey;

  // Create + insert 50k rows in one transaction through the sync triggers.
  var db = openBackground(file, key, verify: verify);
  for (final ddl in ftsSourceDdl) {
    await statement(db, ddl, const [], 'bench_ddl');
  }
  final insertUs = await _timed(
    () => guarded(
      'bench_insert',
      () => db.batch((b) {
        for (final row in data) {
          b.customStatement(
            'INSERT INTO transactions_fts_src '
            '(id, occurred_at, merchant, counterparty, note, amount_text) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            row,
          );
        }
      }),
    ),
  );
  await db.close();

  Future<int> reopen() async {
    final sw = Stopwatch()..start();
    db = openBackground(file, key, verify: verify);
    final n = await scalar(db, 'SELECT count(*) FROM transactions_fts_src');
    sw.stop();
    if (n != benchRows) throw DbContractException('bench_row_count');
    return sw.elapsedMicroseconds;
  }

  // Cold: first createInBackground of the populated file (isolate spawn and
  // the full open sequence included) to the first verified result.
  final coldUs = await reopen();
  final warm = <int>[];
  for (var i = 0; i < 10; i++) {
    await db.close();
    warm.add(await reopen());
  }
  warm.sort();

  Future<List<int>> termPass(
    String sql,
    String stage,
    List<String> terms,
    List<Object?> Function(String term) args,
  ) async {
    final out = <int>[];
    for (var rep = 0; rep < 5; rep++) {
      for (final term in terms) {
        out.add(await _timed(() => query(db, sql, args(term), stage)));
      }
    }
    return out;
  }

  final rank = await _measured(
    () => termPass(_rankQuery, 'bench_rank', benchTerms, (t) => [ftsQuote(t)]),
  );
  final list = await _measured(
    () => termPass(_listQuery, 'bench_list', benchTerms, (t) => [ftsQuote(t)]),
  );
  final short = await _measured(
    () => termPass(_shortQuery, 'bench_short', benchShortTerms, (t) {
      final p = '%$t%';
      return [p, p, p];
    }),
  );

  // §8(b): the short-prefix table, built from the source rows.
  await statement(db, shortPrefixDdl, const [], 'bench_short_ddl');
  final shortBuildUs = await _timed(
    () => statement(db, _shortPrefixFill, const [], 'bench_short_fill'),
  );
  final shortPrefix = await _measured(
    () => termPass(
      _shortPrefixQuery,
      'bench_short_prefix',
      benchShortTerms,
      (t) => [ftsPrefix(t)],
    ),
  );
  var shortPrefixHits = 0;
  for (final term in benchShortTerms) {
    final rows = await query(db, _shortPrefixQuery, [
      ftsPrefix(term),
    ], 'bench_short_hits');
    shortPrefixHits += rows.length;
  }
  await db.close();

  return {
    'open_cold_ms': _ms(coldUs),
    'open_warm_ms': _ms(warm[warm.length ~/ 2]),
    'insert_50k_ms': _ms(insertUs),
    'fts_rank_ms': rank,
    'fts_list_ms': list,
    'like_short_ms': short,
    'short_prefix_ms': shortPrefix,
    'short_prefix_build_ms': _ms(shortBuildUs),
    'short_prefix_hits': shortPrefixHits,
    'passes': benchPasses,
    'db_bytes': file.lengthSync(),
  };
}

/// Information only: one open with a passphrase key (PBKDF2, 256,000
/// iterations) to justify the raw key.
Future<double> _passphraseOpenMs(Directory dir) async {
  final file = File('${dir.path}/bench_pbkdf2.db');
  final key = PassphraseKey(randomHexKey().substring(0, 32));
  var db = openBackground(file, key);
  await statement(db, 'CREATE TABLE t (x INTEGER)');
  await statement(db, 'INSERT INTO t VALUES (1)');
  await db.close();
  final sw = Stopwatch()..start();
  db = openBackground(file, key);
  await scalar(db, 'SELECT count(*) FROM t');
  sw.stop();
  await db.close();
  return _ms(sw.elapsedMicroseconds);
}

String _buildMode() => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

/// Runs everything and returns the single `ZAGHLOL_DB_BENCH` JSON object.
Future<Map<String, Object?>> runDbBenchmark({
  required String env,
  String runId = '',
}) async {
  final dir = await Directory.systemTemp.createTemp('zaghlol_t007_bench_');
  try {
    final probe = openForeground(
      File('${dir.path}/info.db'),
      RawKey(randomHexKey()),
    );
    final info = await libraryInfo(probe);
    await probe.close();

    final enc = await _benchMode(dir, RawKey(randomHexKey()));
    final plain = await _benchMode(dir, const NoKey());
    final pbkdf2 = await _passphraseOpenMs(dir);
    final encP95 = (enc['fts_list_ms']! as List<double>)[1];
    final plainP95 = (plain['fts_list_ms']! as List<double>)[1];
    return {
      'v': 2,
      'run': runId,
      'env': env,
      'build': _buildMode(),
      'os': Platform.operatingSystem,
      'sqlite': info.sqliteVersion,
      'mc': info.mcVersion,
      'rows': benchRows,
      'enc': enc,
      'plain': plain,
      'ratio_list_p95': plainP95 == 0
          ? null
          : (encP95 / plainP95 * 100).round() / 100,
      'pbkdf2_open_ms': pbkdf2,
    };
  } finally {
    await dir.delete(recursive: true);
  }
}

/// Prints the one benchmark line.
void emitBenchmark(Map<String, Object?> result) {
  // ignore: avoid_print
  print('ZAGHLOL_DB_BENCH ${jsonEncode(result)}');
}
