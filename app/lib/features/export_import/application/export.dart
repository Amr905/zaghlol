// T-154: CSV and Excel export (FR-EXP-01/02/05, BR-EXP-01). Pure Dart.
//
// Export is user-initiated and is the only way financial data leaves the
// phone besides encrypted backup. Rules enforced here:
//  * Free gets a preview table only (GoldGate.exportPreviewOnly); no file
//    bytes are produced for Free.
//  * Files are written only through [ExportDestination], which the UI binds
//    to a location the user picked, and only after the user acknowledged
//    the "not encrypted" warning. No temp file is created here.
//  * Amounts are exact decimal strings from minor units, never double,
//    never converted; each row carries its own currency.
//  * Free text is neutralised against CSV/formula injection.
// Nothing here logs; errors never echo cell content.

import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../gold/application/gating.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transaction_repository.dart';

enum ExportFormat { csv, xlsx }

/// Rows shown in the Free preview table.
const int exportPreviewRows = 20;

/// Hard cap on exported rows (keeps memory bounded).
const int exportMaxRows = 200000;

const List<String> exportHeader = [
  'id',
  'date_utc',
  'tz_offset_min',
  'account_id',
  'type',
  'status',
  'amount',
  'currency',
  'original_amount',
  'original_currency',
  'merchant',
  'category_id',
  'source',
  'note',
];

/// Neutralises a cell that a spreadsheet could read as a formula: a leading
/// `=`, `+`, `-`, `@`, tab or CR gets a leading apostrophe. Applied only to
/// free text, never to amounts (which are generated from [Money]).
String neutralizeFormula(String s) {
  if (s.isEmpty) return s;
  const risky = {0x3D, 0x2B, 0x2D, 0x40, 0x09, 0x0D};
  return risky.contains(s.codeUnitAt(0)) ? "'$s" : s;
}

/// One export row as strings, in [exportHeader] order.
List<String> exportRow(TransactionRecord t) {
  final orig = t.originalAmount;
  return [
    t.id,
    t.occurredAt.toUtc().toIso8601String(),
    '${t.occurredTzOffsetMin}',
    t.accountId,
    t.direction.code,
    t.status.code,
    t.amount.toCanonicalString(),
    t.amount.currency.code,
    orig?.toCanonicalString() ?? '',
    orig?.currency.code ?? '',
    neutralizeFormula(t.merchantRaw ?? ''),
    t.categoryId ?? '',
    t.source.code,
    neutralizeFormula(t.note ?? ''),
  ];
}

/// RFC 4180 CSV, UTF-8 with BOM, CRLF line ends (opens Arabic correctly in
/// Excel on Windows).
Uint8List encodeCsv(List<List<String>> rows) {
  final b = StringBuffer();
  for (final r in rows) {
    b.write(r.map(_csvCell).join(','));
    b.write('\r\n');
  }
  final body = utf8.encode(b.toString());
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body]);
}

String _csvCell(String s) {
  if (s.contains(RegExp(r'[",\r\n]'))) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

// ---- XLSX (minimal, uncompressed zip; no dependency) ----

/// Builds a one-sheet .xlsx. Columns listed in [numericColumns] are written
/// as numbers when the value is a plain decimal of at most 15 digits;
/// otherwise as text so no precision is lost.
Uint8List encodeXlsx(
  List<List<String>> rows, {
  Set<int> numericColumns = const {6, 8},
}) {
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  final numRe = RegExp(r'^-?[0-9]+(\.[0-9]+)?$');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final ref = '${_col(c)}${r + 1}';
      final digits = v.replaceAll(RegExp(r'[-.]'), '').length;
      if (r > 0 &&
          numericColumns.contains(c) &&
          numRe.hasMatch(v) &&
          digits <= 15) {
        sheet.write('<c r="$ref"><v>$v</v></c>');
      } else {
        sheet.write(
          '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(v)}</t></is></c>',
        );
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  return _zip({
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Transactions" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '</Relationships>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  });
}

String _col(int i) {
  var s = '';
  var n = i;
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}

String _xml(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ok =
        r == 0x9 ||
        r == 0xA ||
        r == 0xD ||
        (r >= 0x20 && r <= 0xD7FF) ||
        (r >= 0xE000 && r <= 0xFFFD) ||
        (r >= 0x10000 && r <= 0x10FFFF);
    if (!ok) continue;
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      default:
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Stored (method 0) zip writer.
Uint8List _zip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  var count = 0;
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final data = utf8.encode(e.value);
    final crc = _crc32(data);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x0800); // UTF-8 names
    u16(out, 0);
    u16(out, 0);
    u16(out, 0x21); // fixed date 1980-01-01
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, name.length);
    u16(out, 0);
    out
      ..add(name)
      ..add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
    count++;
  }
  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.toBytes();
}

// ---- Service ----

/// Where bytes go: bound by the UI to the location the user picked.
abstract interface class ExportDestination {
  Future<void> write(String suggestedName, Uint8List bytes);
}

sealed class ExportOutcome {
  const ExportOutcome();
}

/// Free tier: preview only (header + up to [exportPreviewRows] rows).
final class ExportPreview extends ExportOutcome {
  const ExportPreview(this.header, this.rows, this.totalRows);
  final List<String> header;
  final List<List<String>> rows;
  final int totalRows;
}

final class ExportWritten extends ExportOutcome {
  const ExportWritten(this.fileName, this.rowCount);
  final String fileName;
  final int rowCount;
}

/// The user has not acknowledged the unencrypted-file warning (FR-EXP-05).
final class ExportNeedsWarningAck extends ExportOutcome {
  const ExportNeedsWarningAck();
}

final class ExportTooLarge extends ExportOutcome {
  const ExportTooLarge();
}

class ExportService {
  ExportService(this._repo);
  final TransactionRepository _repo;

  Future<List<TransactionRecord>> _load(
    TransactionFilter filter,
    int max,
  ) async {
    final all = <TransactionRecord>[];
    var offset = 0;
    while (all.length < max) {
      final page = await _repo.query(
        filter: filter,
        page: PageRequest(limit: 500, offset: offset),
      );
      all.addAll(page);
      if (page.length < 500) break;
      offset += 500;
    }
    return all;
  }

  /// Free: preview only. Gold: writes the file to [destination] after
  /// [warningAcknowledged]. [filter] carries date, category and card
  /// (account) filters; soft-deleted rows are never included.
  Future<ExportOutcome> export({
    required EntitlementState entitlement,
    required TransactionFilter filter,
    required ExportFormat format,
    required ExportDestination destination,
    required bool warningAcknowledged,
    DateTime? now,
  }) async {
    if (GoldGate.exportPreviewOnly(entitlement)) {
      final rows = await _load(filter, exportPreviewRows);
      final total = await _repo.count(filter: filter);
      return ExportPreview(
        exportHeader,
        rows.take(exportPreviewRows).map(exportRow).toList(),
        total,
      );
    }
    if (!warningAcknowledged) return const ExportNeedsWarningAck();
    final rows = await _load(filter, exportMaxRows + 1);
    if (rows.length > exportMaxRows) return const ExportTooLarge();
    final table = [exportHeader, ...rows.map(exportRow)];
    final bytes = format == ExportFormat.csv
        ? encodeCsv(table)
        : encodeXlsx(table);
    final d = (now ?? DateTime.now()).toUtc();
    final stamp =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final name =
        'zaghlol-export-$stamp.${format == ExportFormat.csv ? 'csv' : 'xlsx'}';
    await destination.write(name, bytes);
    return ExportWritten(name, rows.length);
  }
}
