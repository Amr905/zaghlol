// T-156: bank PDF statement import (FR-EXP-04), bank-agnostic.
//
// Everything runs on the phone: the PDF is read from memory by a
// [PdfTextExtractor] (no network, no temp file), turned into a table and
// parsed into rows; only the rows are stored.
//
// Privacy rules enforced here:
//  * The picked bytes are overwritten with zeros as soon as the text has
//    been extracted (success or failure), so the plain PDF is not kept.
//  * The password is a parameter of one call. It is never stored, logged or
//    put in a result or error.
//  * Errors are typed kinds; no statement text, amount or file name appears
//    in an exception, summary or `toString`.
//  * Money is integer minor units in the statement currency; nothing is
//    converted.
//  * Scanned PDFs: the extractor passed in may fall back to on-device OCR
//    (see ScannedPdfTextExtractor); this class only sees positioned text.
//  * Where the statement prints a running balance, a row that does not add up
//    to it is not imported and is counted with the invalid rows.
//
// Duplicates: a statement row has a day, not an instant, so a row is a
// duplicate of an existing transaction of the same account when the local
// day, direction, amount and currency match (the description differs
// between an SMS and a statement, so it is not compared). Matching is a
// multiset like T-155: two identical purchases on one day import twice into
// an empty book and zero times when both are already there. Rows are only
// inserted, in one transaction (all or none).

import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../transactions/domain/transaction.dart';
import 'import_csv.dart';

enum StatementImportFailure {
  passwordRequired,
  wrongPassword,
  unreadable,
  noText,

  /// Text was read but no row of a statement table was found.
  noRows,

  /// The user's mapping cannot be used (see [StatementMapping.isValid]).
  badMapping,
  unknownAccount,
  storeFailed,
}

final class StatementImportException implements Exception {
  const StatementImportException(this.kind);
  final StatementImportFailure kind;

  @override
  String toString() => 'StatementImportException(${kind.name})';
}

/// Per-bank saved layouts. The Drift implementation keeps them in the
/// encrypted database.
abstract interface class StatementTemplateStore {
  Future<StatementTemplate?> load(String bankKey);
  Future<void> save(StatementTemplate template);
}

/// A statement read from a PDF but not yet stored: the table and what the
/// reader proposes. Holds statement text in memory only.
final class StatementReading {
  const StatementReading({
    required this.table,
    required this.template,
    required this.bankKey,
  });
  final StatementTable table;

  /// The saved template that was applied, if any.
  final StatementTemplate? template;
  final String bankKey;

  /// True when the user must confirm the columns (no template and no
  /// recognised header).
  bool get needsMapping => !table.confident;

  @override
  String toString() => 'StatementReading';
}

class ImportStatementPdfUseCase {
  ImportStatementPdfUseCase(
    this._extractor,
    this._store,
    this._templates, {
    this.onImported,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PdfTextExtractor _extractor;
  final CsvImportStore _store;
  final StatementTemplateStore _templates;
  final Future<void> Function(String id)? onImported;

  /// The end of a statement whose dates carry no year.
  final DateTime Function() _now;

  /// Reads [bytes] (zeroed before this returns) and finds the table.
  ///
  /// Throws [StatementImportException] with `passwordRequired` for an
  /// encrypted file and no [password], `wrongPassword` for a bad one.
  Future<StatementReading> open(
    Uint8List bytes, {
    required String bankKey,
    String? password,
  }) async {
    final List<PdfTextFragment> fragments;
    try {
      fragments = await _extractor.extract(bytes, password: password);
    } on PdfExtractException catch (e) {
      throw StatementImportException(switch (e.kind) {
        PdfExtractFailureKind.passwordRequired =>
          StatementImportFailure.passwordRequired,
        PdfExtractFailureKind.wrongPassword =>
          StatementImportFailure.wrongPassword,
        PdfExtractFailureKind.unreadable => StatementImportFailure.unreadable,
        PdfExtractFailureKind.noText => StatementImportFailure.noText,
      });
    } on Object {
      throw const StatementImportException(StatementImportFailure.unreadable);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final template = await _templates.load(bankKey);
    final table = buildStatementTable(
      fragments,
      template: template,
      today: _now(),
    );
    if (table.rows.every((r) => r.continuation)) {
      throw const StatementImportException(StatementImportFailure.noRows);
    }
    return StatementReading(table: table, template: template, bankKey: bankKey);
  }

  /// Parses the rows with [mapping] and stores the new ones on [accountId].
  /// With [dryRun] nothing is written (preview). With [saveTemplate] a
  /// successful real import remembers the layout for this bank.
  Future<ImportSummary> run(
    StatementReading reading,
    StatementMapping mapping, {
    required String accountId,
    bool dryRun = false,
    bool saveTemplate = true,
  }) async {
    if (!mapping.isValid || mapping.roles.length != reading.table.columnCount) {
      throw const StatementImportException(StatementImportFailure.badMapping);
    }
    final parsed = parseStatementRows(reading.table, mapping);
    final newIds = <String>[];
    final ImportSummary summary;
    try {
      summary = await _store.inWriteTransaction(() async {
        if (!(await _store.accountIds()).contains(accountId)) {
          throw const StatementImportException(
            StatementImportFailure.unknownAccount,
          );
        }
        return _apply(parsed, accountId, dryRun, newIds);
      });
    } on StatementImportException {
      rethrow;
    } on Exception {
      throw const StatementImportException(StatementImportFailure.storeFailed);
    }
    if (!dryRun && saveTemplate) {
      try {
        await _templates.save(
          StatementTemplate(
            bankKey: reading.bankKey,
            cutPoints: reading.table.cutPoints,
            mapping: mapping,
          ),
        );
      } on Exception {
        // The rows are saved; the user will be asked to map again next time.
      }
    }
    final hook = onImported;
    if (hook != null) {
      for (final id in newIds) {
        await hook(id);
      }
    }
    return summary;
  }

  Future<ImportSummary> _apply(
    StatementParseResult parsed,
    String accountId,
    bool dryRun,
    List<String> newIds,
  ) async {
    // Existing rows per local day, read once.
    final existing = <String, Map<String, int>>{};
    final seen = <String, int>{};
    var imported = 0;
    var duplicates = 0;
    DateTime? earliest;
    DateTime? latest;
    for (final r in parsed.rows) {
      final start = DateTime(r.date.year, r.date.month, r.date.day);
      final end = DateTime(r.date.year, r.date.month, r.date.day + 1);
      final noon = DateTime(r.date.year, r.date.month, r.date.day, 12);
      if (earliest == null || noon.isBefore(earliest)) earliest = noon;
      if (latest == null || noon.isAfter(latest)) latest = noon;
      final dir = r.isExpense ? TxnDirection.expense : TxnDirection.income;
      final day = '${r.date.year}-${r.date.month}-${r.date.day}';
      final counts = existing[day] ??= await _existingCounts(
        accountId,
        start,
        end,
      );
      final k = '$day|${_key(dir, r.amount)}';
      final nth = seen.update(k, (n) => n + 1, ifAbsent: () => 1);
      if (nth <= (counts[_key(dir, r.amount)] ?? 0)) {
        duplicates++;
        continue;
      }
      if (!dryRun) {
        newIds.add(
          await _store.insert(
            ImportedTxn(
              accountId: accountId,
              direction: dir,
              status: TxnStatus.posted,
              amount: r.amount,
              occurredAt: noon.toUtc(),
              occurredTzOffsetMin: noon.timeZoneOffset.inMinutes,
              merchant: r.description.isEmpty ? null : r.description,
              source: TxnSource.pdf,
            ),
          ),
        );
      }
      imported++;
    }
    final byProblem = <ImportRowProblem, int>{};
    parsed.problems.forEach((p, n) {
      // A balance mismatch is shown with the amount problems: the amount or
      // the direction of that row cannot be trusted.
      final mapped = p == StatementRowProblem.badDate
          ? ImportRowProblem.badDate
          : ImportRowProblem.badAmount;
      byProblem.update(mapped, (c) => c + n, ifAbsent: () => n);
    });
    return ImportSummary(
      totalRows: parsed.totalRows,
      imported: imported,
      duplicates: duplicates,
      invalid: parsed.invalid,
      invalidByProblem: byProblem,
      invalidRows: parsed.invalidRows,
      earliest: earliest,
      latest: latest,
    );
  }

  Future<Map<String, int>> _existingCounts(
    String accountId,
    DateTime start,
    DateTime end,
  ) async {
    final counts = <String, int>{};
    for (final e in await _store.existingBetween(
      accountId,
      start.toUtc().millisecondsSinceEpoch,
      end.toUtc().millisecondsSinceEpoch,
      settledOnly: true,
    )) {
      counts.update(
        _key(e.direction, e.amount),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  /// Built from storage terms (minor + currency), never from source text.
  static String _key(TxnDirection d, Money amount) {
    final s = amount.toStorage();
    return '${d.code}|${s.minor}|${s.currency}';
  }
}
