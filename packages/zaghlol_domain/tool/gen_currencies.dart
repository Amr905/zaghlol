// Regenerates the bundled ISO 4217 table (T-012). Run from
// packages/zaghlol_domain:
//
//   dart run tool/gen_currencies.dart                  normal refresh
//   dart run tool/gen_currencies.dart --fresh          first genuine snapshot
//   dart run tool/gen_currencies.dart --allow-change=ABC,DEF
//
// 1. Reads the pinned SIX List One snapshot, tool/iso4217/list-one.xml.
// 2. Merges it into lib/money/data/currencies.json, append-only: codes that
//    left List One stay in the table with status "historic". A changed
//    exponent or numeric for an existing code is an error unless the code
//    is listed in --allow-change (an exponent change also needs a data
//    migration task).
// 3. Writes lib/money/src/iso4217_table.g.dart (a const list) from the JSON,
//    because pure Dart cannot read assets at runtime.
//
// --fresh ignores the committed JSON and builds the table from the snapshot
// alone. Use it exactly once: when the reconstructed placeholder snapshot is
// replaced by the first genuine SIX download, so no code that exists only
// in the placeholder survives as "historic". After that run, regenerate
// `_baselineCodes` in test/money/iso4217_table_test.dart from the new JSON
// (every code, active and historic), and list the codes that changed
// versus the placeholder in the PR. All later refreshes run without
// --fresh.
//
// Every value written into Dart source is validated (codes ^[A-Z]{3}$,
// numeric 1..999, exponent 0..4, published YYYY-MM[-DD]). Tests regenerate
// both outputs in memory and require them to be byte-identical to the
// committed files.
import 'dart:convert';
import 'dart:io';

const String xmlPath = 'tool/iso4217/list-one.xml';
const String jsonPath = 'lib/money/data/currencies.json';
const String dartPath = 'lib/money/src/iso4217_table.g.dart';
const String sourceName = 'ISO 4217 List One';
const String _allowFlag = '--allow-change=';

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
final RegExp _date = RegExp(r'^\d{4}-\d{2}(-\d{2})?$');

/// XML comments, CDATA sections and the DOCTYPE (with any internal subset)
/// are removed before matching, so nothing inside them is parsed.
final RegExp _ignored = RegExp(
  r'<!--.*?-->|<!\[CDATA\[.*?\]\]>|<!DOCTYPE[^>\[]*(\[.*?\])?\s*>',
  dotAll: true,
);

/// Validates the publication date. It is the only free-text value that
/// reaches generated Dart source, so anything but `YYYY-MM[-DD]` (newlines,
/// `*/`, quotes...) is rejected.
String checkPublished(String value) {
  if (!_date.hasMatch(value)) {
    throw const FormatException('published must be YYYY-MM or YYYY-MM-DD');
  }
  return value;
}

/// Validates a row before it is used or emitted: an ISO-shaped code,
/// numeric 1..999 and exponent 0..4.
CurrencyRow checkRow(CurrencyRow row) {
  final okCode = _code.hasMatch(row.code);
  final okNumeric = row.numeric >= 1 && row.numeric <= 999;
  final okExponent = row.exponent >= 0 && row.exponent <= 4;
  if (!okCode || !okNumeric || !okExponent) {
    throw const FormatException('invalid currency row');
  }
  return row;
}

/// Parses SIX List One XML with regular expressions (no xml dependency).
///
/// Keeps every code with a numeric minor unit, once (List One repeats codes
/// per country). Entries without a code (e.g. Antarctica) and entries with
/// `N.A.` minor units (precious metals, XDR, XSU, XUA, XBA..XBD, XTS, XXX)
/// are skipped. Conflicting repeats, a malformed `Pblshd` date and values
/// out of range are errors.
CurrencyTable parseListOne(String source) {
  final xml = source.replaceAll(_ignored, '');
  final published = _published.firstMatch(xml)?.group(1);
  if (published == null) {
    throw const FormatException('List One: missing Pblshd attribute');
  }
  checkPublished(published);
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
      throw const FormatException('List One: bad entry');
    }
    if (minorUnits.length > 1 || numeric.length > 3) {
      throw FormatException('List One: value out of range for $code');
    }
    final row = CurrencyRow(
      code: code,
      numeric: int.parse(numeric),
      exponent: int.parse(minorUnits),
      active: true,
      fund: _fund.hasMatch(body),
    );
    checkRow(row);
    final previous = byCode[code];
    if (previous != null && previous != row) {
      throw FormatException('List One: conflicting entries for $code');
    }
    byCode[code] = row;
  }
  return CurrencyTable(published, _sorted(byCode.values));
}

/// Merges a List One snapshot into the previous table, append-only: every
/// code in [listOne] is active with its List One data, and every previous
/// code missing from [listOne] is kept as historic. Nothing is ever deleted.
///
/// Throws [FormatException] when an existing code's exponent or numeric
/// changes, unless the code is in [allowChanged]: stored `*_minor` values
/// would be read at the wrong scale, so an exponent change needs a data
/// migration task, not just a table refresh.
///
/// With [previous] null (the `--fresh` mode) the result is exactly
/// [listOne].
CurrencyTable mergeAppendOnly({
  required CurrencyTable listOne,
  CurrencyTable? previous,
  Set<String> allowChanged = const {},
}) {
  final byCode = <String, CurrencyRow>{};
  for (final row in listOne.rows) {
    byCode[checkRow(row).code] = row;
  }
  for (final row in previous?.rows ?? const <CurrencyRow>[]) {
    final next = byCode[row.code];
    if (next == null) {
      byCode[row.code] = checkRow(row).asHistoric();
      continue;
    }
    final sameExponent = next.exponent == row.exponent;
    final changed = !sameExponent || next.numeric != row.numeric;
    if (changed && !allowChanged.contains(row.code)) {
      throw FormatException('${row.code}: exponent or numeric changed');
    }
  }
  final published = checkPublished(listOne.published);
  return CurrencyTable(published, _sorted(byCode.values));
}

List<CurrencyRow> _sorted(Iterable<CurrencyRow> rows) {
  final list = rows.toList();
  list.sort((a, b) => a.code.compareTo(b.code));
  return list;
}

/// Renders the table as `currencies.json` (one currency per line).
String renderJson(CurrencyTable table) {
  _validate(table);
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

/// Parses `currencies.json` and validates the date and every row.
CurrencyTable parseJson(String json) {
  final root = jsonDecode(json);
  if (root is! Map<String, Object?>) {
    throw const FormatException('currencies.json: not an object');
  }
  final published = root['published'];
  final items = root['currencies'];
  if (published is! String || items is! List<Object?>) {
    throw const FormatException('currencies.json: bad header');
  }
  checkPublished(published);
  final rows = <CurrencyRow>[];
  for (final item in items) {
    rows.add(_parseRow(item));
  }
  return CurrencyTable(published, rows);
}

CurrencyRow _parseRow(Object? item) {
  if (item is! Map<String, Object?>) {
    throw const FormatException('currencies.json: bad row');
  }
  final code = item['code'];
  final numeric = item['numeric'];
  final exponent = item['exponent'];
  final status = item['status'];
  final fund = item['fund'] ?? false;
  final validStatus = status == 'active' || status == 'historic';
  if (code is! String || numeric is! int || exponent is! int) {
    throw const FormatException('currencies.json: bad row');
  }
  if (!validStatus || fund is! bool) {
    throw const FormatException('currencies.json: bad row');
  }
  final row = CurrencyRow(
    code: code,
    numeric: numeric,
    exponent: exponent,
    active: status == 'active',
    fund: fund,
  );
  return checkRow(row);
}

/// Every value that reaches generated source is validated here, even when
/// the table did not come from [parseListOne] or [parseJson].
void _validate(CurrencyTable table) {
  checkPublished(table.published);
  table.rows.forEach(checkRow);
}

/// Renders the const Dart table from the JSON table.
String renderDart(CurrencyTable table) {
  _validate(table);
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

void main(List<String> args) {
  var fresh = false;
  var allowChanged = <String>{};
  for (final arg in args) {
    if (arg == '--fresh') {
      fresh = true;
    } else if (arg.startsWith(_allowFlag)) {
      allowChanged = arg.substring(_allowFlag.length).split(',').toSet();
    } else {
      stderr.writeln('usage: gen_currencies.dart [--fresh] [$_allowFlag...]');
      exitCode = 64;
      return;
    }
  }
  final listOne = parseListOne(File(xmlPath).readAsStringSync());
  final jsonFile = File(jsonPath);
  CurrencyTable? previous;
  if (!fresh && jsonFile.existsSync()) {
    previous = parseJson(jsonFile.readAsStringSync());
  }
  final merged = mergeAppendOnly(
    listOne: listOne,
    previous: previous,
    allowChanged: allowChanged,
  );
  jsonFile.writeAsStringSync(renderJson(merged));
  File(dartPath).writeAsStringSync(renderDart(merged));
  stdout.writeln('Wrote ${merged.rows.length} currencies.');
}
