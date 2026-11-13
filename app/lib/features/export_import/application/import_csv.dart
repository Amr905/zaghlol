// T-155: Zaghlol CSV import (FR-EXP-03). Pure Dart.
//
// Reads exactly the file T-154's `encodeCsv` writes and stores its rows as
// transactions (source `csv`). Rules:
//  * Untrusted input: byte, row and cell caps; strict UTF-8; the header must
//    equal [exportHeader]; every field is validated; nothing a row contains
//    is ever echoed in an error or summary (only row numbers and reasons).
//  * Amounts are parsed exactly with [Money.parse] after digit
//    normalisation (never through a double) and are never converted.
//  * Never overwrites: rows are only inserted. A row that matches an
//    existing transaction (same account, instant, type, amount, currency
//    and merchant) is skipped as a duplicate and counted. Matching is a
//    multiset: a file holding the same purchase twice imports it twice into
//    an empty book and zero times into a book that already has both.
//  * Keys are built from [Money.toStorage] (minor + currency), never from
//    the source text (T-012 F5).
//  * Cells are text, never evaluated. A leading apostrophe that
//    [neutralizeFormula] added is removed again.
//  * The whole import is one write transaction: all valid rows or none.
// Nothing here logs.

import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../transactions/domain/transaction.dart';
import 'export.dart';

/// Largest file accepted, in bytes.
const int importMaxBytes = 64 * 1024 * 1024;

/// Most data rows accepted (the export cap).
const int importMaxRows = exportMaxRows;

/// Longest cell, in code points; a longer one invalidates its row.
const int importMaxCellRunes = 4096;

/// Longest stored merchant text and note, in code points (as the
/// repository stores them).
const int importMaxMerchantRunes = 200;
const int importMaxNoteRunes = 1000;

/// Row numbers listed in [ImportSummary.invalidRows].
const int importMaxListedRows = 100;

/// A whole-file failure. Codes only; never any file content.
final class ImportCsvException extends SafeException {
  ImportCsvException(super.code);

  static const String tooLarge = 'IMPORT_TOO_LARGE';
  static const String tooManyRows = 'IMPORT_TOO_MANY_ROWS';
  static const String notUtf8 = 'IMPORT_NOT_UTF8';
  static const String malformed = 'IMPORT_MALFORMED_CSV';
  static const String badHeader = 'IMPORT_BAD_HEADER';
}

/// Why a row was not imported.
enum ImportRowProblem {
  columnCount,
  cellTooLong,
  badDate,
  badOffset,
  badDirection,
  badStatus,
  badAmount,
  badOriginalAmount,
  unknownAccount,
}

/// A validated row ready to store.
final class ImportedTxn {
  const ImportedTxn({
    required this.accountId,
    required this.direction,
    required this.status,
    required this.amount,
    required this.occurredAt,
    required this.occurredTzOffsetMin,
    this.originalAmount,
    this.merchant,
    this.categoryId,
    this.note,
  });

  final String accountId;
  final TxnDirection direction;
  final TxnStatus status;
  final Money amount;
  final Money? originalAmount;
  final DateTime occurredAt;
  final int occurredTzOffsetMin;
  final String? merchant;
  final String? categoryId;
  final String? note;

  @override
  String toString() => 'ImportedTxn';
}

/// What an existing transaction looks like to the duplicate check.
final class ExistingTxnKey {
  const ExistingTxnKey({
    required this.direction,
    required this.amount,
    this.merchant,
  });
  final TxnDirection direction;
  final Money amount;
  final String? merchant;
}

/// The database port. [inWriteTransaction] wraps every other call.
abstract interface class CsvImportStore {
  Future<T> inWriteTransaction<T>(Future<T> Function() body);

  /// Ids of existing accounts / categories (an import never creates them).
  Future<Set<String>> accountIds();
  Future<Set<String>> categoryIds();

  /// Live transactions of [accountId] at exactly [occurredAtMs].
  Future<List<ExistingTxnKey>> existingAt(String accountId, int occurredAtMs);

  Future<void> insert(ImportedTxn row);
}

final class ImportSummary {
  const ImportSummary({
    required this.totalRows,
    required this.imported,
    required this.duplicates,
    required this.invalid,
    required this.invalidByProblem,
    required this.invalidRows,
  });

  /// Data rows in the file (header excluded).
  final int totalRows;
  final int imported;

  /// Skipped because they already exist.
  final int duplicates;
  final int invalid;
  final Map<ImportRowProblem, int> invalidByProblem;

  /// 1-based data row numbers of the first invalid rows (capped).
  final List<int> invalidRows;
}

class ImportCsvUseCase {
  ImportCsvUseCase(this._store);
  final CsvImportStore _store;

  Future<ImportSummary> run(Uint8List bytes) async {
    final table = parseCsv(bytes);
    final header = table.first;
    if (header.length != exportHeader.length) {
      throw ImportCsvException(ImportCsvException.badHeader);
    }
    for (var i = 0; i < header.length; i++) {
      if (header[i] != exportHeader[i]) {
        throw ImportCsvException(ImportCsvException.badHeader);
      }
    }
    final dataRows = table.length - 1;
    if (dataRows > importMaxRows) {
      throw ImportCsvException(ImportCsvException.tooManyRows);
    }
    return _store.inWriteTransaction(() async {
      final accounts = await _store.accountIds();
      final categories = await _store.categoryIds();
      final problems = <ImportRowProblem, int>{};
      final invalidRows = <int>[];
      final valid = <ImportedTxn>[];
      var invalid = 0;
      for (var i = 1; i < table.length; i++) {
        final r = table[i];
        final p = r.length != exportHeader.length
            ? (ImportRowProblem.columnCount, null)
            : _validate(r, accounts, categories);
        if (p.$2 != null) {
          valid.add(p.$2!);
        } else {
          invalid++;
          problems.update(p.$1!, (n) => n + 1, ifAbsent: () => 1);
          if (invalidRows.length < importMaxListedRows) invalidRows.add(i);
        }
      }
      // Existing rows per (account, instant), read once.
      final existing = <String, Map<String, int>>{};
      for (final v in valid) {
        final slot = '${v.accountId}|${_ms(v.occurredAt)}';
        if (existing.containsKey(slot)) continue;
        final counts = <String, int>{};
        for (final e in await _store.existingAt(
          v.accountId,
          _ms(v.occurredAt),
        )) {
          counts.update(
            _key(e.direction, e.amount, e.merchant),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
        existing[slot] = counts;
      }
      final seen = <String, int>{};
      var imported = 0;
      var duplicates = 0;
      for (final v in valid) {
        final slot = '${v.accountId}|${_ms(v.occurredAt)}';
        final k = '$slot|${_key(v.direction, v.amount, v.merchant)}';
        final nth = seen.update(k, (n) => n + 1, ifAbsent: () => 1);
        final have =
            existing[slot]![_key(v.direction, v.amount, v.merchant)] ?? 0;
        if (nth <= have) {
          duplicates++;
        } else {
          await _store.insert(v);
          imported++;
        }
      }
      return ImportSummary(
        totalRows: dataRows,
        imported: imported,
        duplicates: duplicates,
        invalid: invalid,
        invalidByProblem: problems,
        invalidRows: invalidRows,
      );
    });
  }

  static int _ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;

  /// Built from storage terms, never from source text.
  static String _key(TxnDirection d, Money amount, String? merchant) {
    final s = amount.toStorage();
    return '${d.code}|${s.minor}|${s.currency}|${merchant ?? ''}';
  }

  (ImportRowProblem?, ImportedTxn?) _validate(
    List<String> r,
    Set<String> accounts,
    Set<String> categories,
  ) {
    for (final c in r) {
      if (c.runes.length > importMaxCellRunes) {
        return (ImportRowProblem.cellTooLong, null);
      }
    }
    final date = _parseDate(_digits(r[1].trim()));
    if (date == null) return (ImportRowProblem.badDate, null);
    final off = int.tryParse(_digits(r[2].trim()));
    if (off == null || off < -1080 || off > 1080) {
      return (ImportRowProblem.badOffset, null);
    }
    final accountId = r[3].trim();
    if (!accounts.contains(accountId)) {
      return (ImportRowProblem.unknownAccount, null);
    }
    final direction = _enum(TxnDirection.values, (e) => e.code, r[4].trim());
    if (direction == null) return (ImportRowProblem.badDirection, null);
    final status = _enum(TxnStatus.values, (e) => e.code, r[5].trim());
    if (status == null) return (ImportRowProblem.badStatus, null);
    final amount = _money(r[6], r[7]);
    if (amount == null) return (ImportRowProblem.badAmount, null);
    Money? original;
    if (r[8].trim().isNotEmpty || r[9].trim().isNotEmpty) {
      original = _money(r[8], r[9]);
      if (original == null) return (ImportRowProblem.badOriginalAmount, null);
    }
    final categoryId = r[11].trim();
    return (
      null,
      ImportedTxn(
        accountId: accountId,
        direction: direction,
        status: status,
        amount: amount,
        originalAmount: original,
        occurredAt: date,
        occurredTzOffsetMin: off,
        merchant: _text(r[10], importMaxMerchantRunes),
        categoryId: categories.contains(categoryId) ? categoryId : null,
        note: _text(r[13], importMaxNoteRunes),
      ),
    );
  }

  static T? _enum<T>(List<T> values, String Function(T) code, String s) {
    for (final v in values) {
      if (code(v) == s) return v;
    }
    return null;
  }

  /// Exact decimal -> [Money]; negative amounts are not valid (the export
  /// never writes one and the table forbids them).
  static Money? _money(String amount, String currency) {
    final c = Currency.tryOf(currency.trim().toUpperCase());
    if (c == null) return null;
    final m = Money.tryParse(_digits(amount.trim()), c);
    if (m == null || m.toStorage().minor < 0) return null;
    return m;
  }

  /// UTC instant (`...Z`), 2000-01-01 up to 2100-01-01.
  static DateTime? _parseDate(String s) {
    if (!s.endsWith('Z')) return null;
    final d = DateTime.tryParse(s);
    if (d == null || !d.isUtc) return null;
    if (d.year < 2000 || d.year > 2099) return null;
    return d;
  }

  /// Removes the apostrophe [neutralizeFormula] added, drops control
  /// characters, trims, cuts to [maxRunes]; empty becomes null.
  static String? _text(String s, int maxRunes) {
    var t = s;
    if (t.length > 1 && t.codeUnitAt(0) == 0x27) {
      const risky = {0x3D, 0x2B, 0x2D, 0x40, 0x09, 0x0D};
      if (risky.contains(t.codeUnitAt(1))) t = t.substring(1);
    }
    t = String.fromCharCodes(
      t.runes.where((c) => !(c < 0x20 && c != 0x0A) && c != 0x7F),
    ).trim();
    if (t.isEmpty) return null;
    final runes = t.runes;
    return runes.length <= maxRunes
        ? t
        : String.fromCharCodes(runes.take(maxRunes));
  }

  /// Arabic-Indic and extended digits and the decimal separator to ASCII.
  static String _digits(String s) {
    final b = StringBuffer();
    for (final c in s.runes) {
      if (c >= 0x0660 && c <= 0x0669) {
        b.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        b.writeCharCode(0x30 + c - 0x06F0);
      } else if (c == 0x066B) {
        b.write('.');
      } else if (c == 0x2212) {
        b.write('-');
      } else {
        b.writeCharCode(c);
      }
    }
    return b.toString();
  }
}

/// Strict RFC 4180 reader: optional UTF-8 BOM, CRLF or LF, quoted cells with
/// `""`. Blank lines are skipped. Throws [ImportCsvException]; the file must
/// have at least a header.
List<List<String>> parseCsv(Uint8List bytes) {
  if (bytes.length > importMaxBytes) {
    throw ImportCsvException(ImportCsvException.tooLarge);
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final String text;
  try {
    text = utf8.decode(
      Uint8List.sublistView(bytes, start),
      allowMalformed: false,
    );
  } on FormatException {
    throw ImportCsvException(ImportCsvException.notUtf8);
  }
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var quotedCell = false;
  var any = false; // the current line has content
  void endCell() {
    row.add(cell.toString());
    cell.clear();
    quotedCell = false;
  }

  void endRow() {
    if (any) {
      endCell();
      rows.add(row);
      if (rows.length > importMaxRows + 1) {
        throw ImportCsvException(ImportCsvException.tooManyRows);
      }
    }
    row = <String>[];
    any = false;
  }

  final n = text.length;
  for (var i = 0; i < n; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
        if (cell.isNotEmpty || quotedCell) {
          throw ImportCsvException(ImportCsvException.malformed);
        }
        inQuotes = true;
        quotedCell = true;
        any = true;
      case ',':
        any = true;
        endCell();
      case '\r':
        if (i + 1 < n && text[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        if (quotedCell) {
          throw ImportCsvException(ImportCsvException.malformed);
        }
        any = true;
        cell.write(ch);
    }
  }
  if (inQuotes) throw ImportCsvException(ImportCsvException.malformed);
  endRow();
  if (rows.isEmpty) throw ImportCsvException(ImportCsvException.badHeader);
  return rows;
}
