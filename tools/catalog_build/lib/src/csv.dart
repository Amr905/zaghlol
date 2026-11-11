// RFC 4180 reader and writer for the catalog CSV (comma separated, `"`
// quoting with `""`, UTF-8, optional BOM, LF or CRLF). The columns are the
// ones the backend's CatalogSeedCsv reads (backend/src/Zaghlol.Application/
// Catalog/CatalogSeed.cs), in the same order.

/// The seed CSV header, in order.
const List<String> seedColumns = [
  'entity',
  'code',
  'nameAr',
  'nameEn',
  'icon',
  'color',
  'bucket',
  'sort',
  'canonical',
  'category',
  'alias',
  'match',
  'keyword',
  'lang',
  'weight',
];

/// One CSV row: its 1-based line and the cells by column name.
final class CsvRow {
  CsvRow(this.line, this.cells);
  final int line;
  final Map<String, String> cells;
  String operator [](String column) => cells[column] ?? '';
}

/// A malformed CSV (a message with a line number, never cell content).
final class CsvFormatException implements Exception {
  CsvFormatException(this.message);
  final String message;
  @override
  String toString() => 'CsvFormatException: $message';
}

/// Parses [text]; the first row must contain every column of [seedColumns]
/// (any order, no unknown columns). Blank lines are skipped.
List<CsvRow> parseCsv(String text) {
  final rows = <(int, List<String>)>[];
  var cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var hasContent = false;
  var line = 1;
  var rowLine = 1;
  final src = text.startsWith('﻿') ? text.substring(1) : text;

  void endRow() {
    if (hasContent) {
      cells.add(cell.toString());
      rows.add((rowLine, cells));
      cells = <String>[];
    }
    cell.clear();
    hasContent = false;
  }

  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (quoted) {
      if (c == '"' && i + 1 < src.length && src[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        if (c == '\n') line++;
        cell.write(c);
      }
      continue;
    }
    switch (c) {
      case '"':
        quoted = true;
        hasContent = true;
      case ',':
        hasContent = true;
        cells.add(cell.toString());
        cell.clear();
      case '\r':
        break;
      case '\n':
        endRow();
        line++;
        rowLine = line;
      default:
        hasContent = true;
        cell.write(c);
    }
  }
  if (quoted) throw CsvFormatException('unterminated quote at line $rowLine');
  endRow();
  if (rows.isEmpty) throw CsvFormatException('empty file');
  final header = rows.first.$2;
  if (header.length != seedColumns.length ||
      !seedColumns.every(header.contains)) {
    throw CsvFormatException('header must be: ${seedColumns.join(',')}');
  }
  return [
    for (final (n, r) in rows.skip(1))
      CsvRow(n, {
        for (var i = 0; i < header.length; i++)
          header[i]: i < r.length ? r[i] : '',
      }),
  ];
}

/// Writes one CSV line (no trailing newline), quoting cells that need it.
String csvLine(List<String> cells) => cells.map(_quote).join(',');

String _quote(String s) =>
    s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
