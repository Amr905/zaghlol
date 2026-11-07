// Regenerates the bundled ISO 4217 table (T-012).
//
//   dart run tool/gen_currencies.dart     (from packages/zaghlol_domain)
//
// 1. Reads the pinned SIX List One snapshot, tool/iso4217/list-one.xml.
// 2. Merges it into lib/money/data/currencies.json, append-only: codes that
//    left List One stay in the table with status "historic".
// 3. Writes lib/money/src/iso4217_table.g.dart (a const list) from the JSON,
//    because pure Dart cannot read assets at runtime.
//
// Tests regenerate both outputs in memory and require them to be
// byte-identical to the committed files.
import 'dart:convert';
import 'dart:io';

const String xmlPath = 'tool/iso4217/list-one.xml';
const String jsonPath = 'lib/money/data/currencies.json';
const String dartPath = 'lib/money/src/iso4217_table.g.dart';
const String sourceName = 'ISO 4217 List One';

/// One row of the currency table.
final class CurrencyRow {
  const CurrencyRow({
    required this.code,
    required this.numeric,
    required this.exponent,
    required this.active,
    required this.fund,
  });

  final String code;
  final int numeric;
  final int exponent;
  final bool active;
  final bool fund;

  CurrencyRow asHistoric() {
    return CurrencyRow(
      code: code,
      numeric: numeric,
      exponent: exponent,
      active: false,
      fund: fund,
    );
  }

  (String, int, int, bool, bool) get _key {
    return (code, numeric, exponent, active, fund);
  }

  @override
  bool operator ==(Object other) => other is CurrencyRow && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() => '$code/$numeric/$exponent/$active/$fund';
}

/// A parsed table: publication date of the snapshot plus rows by code.
final class CurrencyTable {
  const CurrencyTable(this.published, this.rows);

  final String published;

  /// Sorted by code, one row per code.
  final List<CurrencyRow> rows;
}

final RegExp _published = RegExp(r'<ISO_4217\s+Pblshd="([^"]*)"');
final RegExp _entry = RegExp(r'<CcyNtry>(.*?)</CcyNtry>', dotAll: true);
final RegExp _ccy = RegExp(r'<Ccy>\s*([^<]*?)\s*</Ccy>');
final RegExp _nbr = RegExp(r'<CcyNbr>\s*([^<]*?)\s*</CcyNbr>');
final RegExp _mnr = RegExp(r'<CcyMnrUnts>\s*([^<]*?)\s*</CcyMnrUnts>');
final RegExp _fund = RegExp(r'<CcyNm[^>]*\bIsFund="true"');
final RegExp _code = RegExp(r'^[A-Z]{3}$');
final RegExp _digits = RegExp(r'^[0-9]+$');

/// Parses SIX List One XML with regular expressions (no xml dependency).
///
/// Keeps every code with a numeric minor unit, once (List One repeats codes
/// per country). Entries without a code (e.g. Antarctica) and entries with
/// `N.A.` minor units (precious metals, XDR, XSU, XUA, XBA..XBD, XTS, XXX)
/// are skipped. Conflicting repeats are an error.
CurrencyTable parseListOne(String xml) {
  final published = _published.firstMatch(xml)?.group(1);
  if (published == null) {
    throw const FormatException('List One: missing Pblshd attribute');
  }
  final byCode = <String, CurrencyRow>{};
  for (final entry in _entry.allMatches(xml)) {
    final body = entry.group(1)!;
    final code = _ccy.firstMatch(body)?.group(1);
    if (code == null) {
      continue;
    }
    final minorUnits = _mnr.firstMatch(body)?.group(1) ?? '';
    if (!_digits.hasMatch(minorUnits)) {
      continue;
    }
    final numeric = _nbr.firstMatch(body)?.group(1) ?? '';
    if (!_code.hasMatch(code) || !_digits.hasMatch(numeric)) {
      throw FormatException('List One: bad entry for $code');
    }
    final row = CurrencyRow(
      code: code,
      numeric: int.parse(numeric),
      exponent: int.parse(minorUnits),
      active: true,
      fund: _fund.hasMatch(body),
    );
    final previous = byCode[code];
    if (previous != null && previous != row) {
      throw FormatException('List One: conflicting entries for $code');
    }
    byCode[code] = row;
  }
  return CurrencyTable(published, _sorted(byCode.values));
}

/// Merges a fresh List One snapshot into the previous table, append-only:
/// every code in [listOne] is active with its List One data, and every
/// previous code missing from [listOne] is kept as historic. Nothing is
/// ever deleted.
CurrencyTable mergeAppendOnly(CurrencyTable listOne, CurrencyTable? previous) {
  final byCode = <String, CurrencyRow>{};
  for (final row in listOne.rows) {
    byCode[row.code] = row;
  }
  for (final row in previous?.rows ?? const <CurrencyRow>[]) {
    byCode.putIfAbsent(row.code, row.asHistoric);
  }
  return CurrencyTable(listOne.published, _sorted(byCode.values));
}

List<CurrencyRow> _sorted(Iterable<CurrencyRow> rows) {
  final list = rows.toList();
  list.sort((a, b) => a.code.compareTo(b.code));
  return list;
}

/// Renders the table as `currencies.json` (one currency per line).
String renderJson(CurrencyTable table) {
  final out = StringBuffer();
  out.writeln('{');
  out.writeln('  "source": ${jsonEncode(sourceName)},');
  out.writeln('  "published": ${jsonEncode(table.published)},');
  out.writeln('  "currencies": [');
  for (var i = 0; i < table.rows.length; i++) {
    final row = table.rows[i];
    final code = '"code": "${row.code}"';
    final numeric = '"numeric": ${row.numeric}';
    final exponent = '"exponent": ${row.exponent}';
    final status = '"status": "${row.active ? 'active' : 'historic'}"';
    final fund = row.fund ? ', "fund": true' : '';
    final comma = i == table.rows.length - 1 ? '' : ',';
    out.writeln('    {$code, $numeric, $exponent, $status$fund}$comma');
  }
  out.writeln('  ]');
  out.writeln('}');
  return out.toString();
}

/// Parses `currencies.json` and validates every row.
CurrencyTable parseJson(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final published = root['published'] as String;
  final rows = <CurrencyRow>[];
  for (final item in root['currencies'] as List<Object?>) {
    final map = item as Map<String, Object?>;
    final code = map['code'] as String;
    final status = map['status'] as String;
    final validStatus = status == 'active' || status == 'historic';
    if (!_code.hasMatch(code) || !validStatus) {
      throw FormatException('currencies.json: bad row for $code');
    }
    final row = CurrencyRow(
      code: code,
      numeric: map['numeric'] as int,
      exponent: map['exponent'] as int,
      active: status == 'active',
      fund: map['fund'] == true,
    );
    rows.add(row);
  }
  return CurrencyTable(published, rows);
}

/// Renders the const Dart table from the JSON table.
String renderDart(CurrencyTable table) {
  final out = StringBuffer();
  out.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.');
  out.writeln('// Source: lib/money/data/currencies.json');
  out.writeln('// ($sourceName, published ${table.published}).');
  out.writeln('// Regenerate: dart run tool/gen_currencies.dart');
  out.writeln();
  out.writeln('/// ISO 4217 rows (code, numeric, exponent, active, fund),');
  out.writeln('/// sorted by code.');
  out.writeln('const List<(String, int, int, bool, bool)> iso4217Table = [');
  for (final row in table.rows) {
    final rest = '${row.numeric}, ${row.exponent}, ${row.active}, ${row.fund}';
    out.writeln("  ('${row.code}', $rest),");
  }
  out.writeln('];');
  return out.toString();
}

void main() {
  final listOne = parseListOne(File(xmlPath).readAsStringSync());
  final jsonFile = File(jsonPath);
  CurrencyTable? previous;
  if (jsonFile.existsSync()) {
    previous = parseJson(jsonFile.readAsStringSync());
  }
  final merged = mergeAppendOnly(listOne, previous);
  jsonFile.writeAsStringSync(renderJson(merged));
  File(dartPath).writeAsStringSync(renderDart(merged));
  stdout.writeln('Wrote ${merged.rows.length} currencies.');
}
