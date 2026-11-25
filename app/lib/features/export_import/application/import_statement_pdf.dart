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
//    to it is never dropped: it is returned for review with the reason, and
//    the user keeps it, fixes its direction or skips it. The same goes for an
//    amount with no sign whose direction no balance can tell. A real import
//    refuses to run while a flagged row has no decision.
//  * When the statement prints no full date and its dates lack a year, the
//    year is only a suggestion (today's); a real import needs the user's
//    confirmed year.
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

  /// A flagged row has no valid decision yet.
  reviewRequired,

  /// The statement has no printed year and the user has not confirmed one.
  yearNotConfirmed,
}

/// What the user decided for a flagged row.
enum StatementReviewChoice {
  /// Import as parsed. Not allowed when the direction is unknown.
  keep,
  asExpense,
  asIncome,
  skip,
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
    return openFragments(fragments, bankKey: bankKey);
  }

  /// Finds the table in text that is already read (photos of a statement,
  /// read by the OCR reader, T-269).
  Future<StatementReading> openFragments(
    List<PdfTextFragment> fragments, {
    required String bankKey,
  }) async {
    if (fragments.isEmpty) {
      throw const StatementImportException(StatementImportFailure.noText);
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

  /// True when the user must confirm the year before a real import.
  static bool needsYear(StatementReading reading) =>
      reading.table.yearSource == StatementYearSource.today;

  /// Parses the rows for the review step: clean rows, flagged rows (with
  /// reason) and problems. Nothing is stored. [confirmedYear] is the year of
  /// the latest dated row when the statement prints none.
  StatementParseResult parse(
    StatementReading reading,
    StatementMapping mapping, {
    int? confirmedYear,
  }) {
    if (!mapping.isValid || mapping.roles.length != reading.table.columnCount) {
      throw const StatementImportException(StatementImportFailure.badMapping);
    }
    final anchor = reading.table.anchorYear;
    final shift = needsYear(reading) && confirmedYear != null && anchor != null
        ? confirmedYear - anchor
        : 0;
    return parseStatementRows(reading.table, mapping, yearShift: shift);
  }

  /// Parses the rows with [mapping] and stores the new ones on [accountId].
  /// With [dryRun] nothing is written (preview). With [saveTemplate] a
  /// successful real import remembers the layout for this bank.
  ///
  /// A real import needs [confirmedYear] when [needsYear] and a decision in
  /// [decisions] (by row number, see [StatementRow.number]) for every flagged
  /// row; otherwise it throws `yearNotConfirmed` / `reviewRequired` and
  /// writes nothing. A decision on a clean row is optional: `skip` drops it,
  /// `asExpense` / `asIncome` flips its direction (T-269). A row that matches
  /// an existing transaction is skipped as a duplicate unless its number is in
  /// [keepDuplicates].
  Future<ImportSummary> run(
    StatementReading reading,
    StatementMapping mapping, {
    required String accountId,
    bool dryRun = false,
    bool saveTemplate = true,
    int? confirmedYear,
    Map<int, StatementReviewChoice> decisions = const {},
    Set<int> keepDuplicates = const {},
  }) async {
    final parsed = parse(reading, mapping, confirmedYear: confirmedYear);
    if (!dryRun) {
      if (needsYear(reading) && confirmedYear == null) {
        throw const StatementImportException(
          StatementImportFailure.yearNotConfirmed,
        );
      }
      for (final r in parsed.review) {
        final d = decisions[r.number];
        if (d == null ||
            (d == StatementReviewChoice.keep && !r.directionKnown)) {
          throw const StatementImportException(
            StatementImportFailure.reviewRequired,
          );
        }
      }
    }
    // Decided rows join the clean ones in table order.
    final accepted = <StatementRow>[];
    for (final r in parsed.rows) {
      final d = decisions[r.number];
      if (d == StatementReviewChoice.skip) continue;
      accepted.add(
        d == StatementReviewChoice.asExpense ||
                d == StatementReviewChoice.asIncome
            ? StatementRow(
                date: r.date,
                description: r.description,
                isExpense: d == StatementReviewChoice.asExpense,
                amount: r.amount,
                balance: r.balance,
                number: r.number,
              )
            : r,
      );
    }
    for (final r in parsed.review) {
      final d = decisions[r.number];
      if (d == null || d == StatementReviewChoice.skip) continue;
      if (d == StatementReviewChoice.keep && !r.directionKnown) continue;
      accepted.add(
        StatementRow(
          date: r.date,
          description: r.description,
          isExpense: switch (d) {
            StatementReviewChoice.asExpense => true,
            StatementReviewChoice.asIncome => false,
            _ => r.isExpense,
          },
          amount: r.amount,
          balance: r.balance,
          number: r.number,
        ),
      );
    }
    accepted.sort((a, b) => a.number.compareTo(b.number));
    final newIds = <String>[];
    final ImportSummary summary;
    try {
      summary = await _store.inWriteTransaction(() async {
        if (!(await _store.accountIds()).contains(accountId)) {
          throw const StatementImportException(
            StatementImportFailure.unknownAccount,
          );
        }
        return _apply(
          parsed,
          accepted,
          accountId,
          dryRun,
          newIds,
          decisions,
          keepDuplicates,
        );
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
    List<StatementRow> accepted,
    String accountId,
    bool dryRun,
    List<String> newIds,
    Map<int, StatementReviewChoice> decisions,
    Set<int> keepDuplicates,
  ) async {
    final duplicateRows = <int>[];
    // Existing rows per local day, read once.
    final existing = <String, Map<String, int>>{};
    final seen = <String, int>{};
    var imported = 0;
    var duplicates = 0;
    DateTime? earliest;
    DateTime? latest;
    for (final r in accepted) {
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
        duplicateRows.add(r.number);
        if (!keepDuplicates.contains(r.number)) {
          duplicates++;
          continue;
        }
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
      final mapped = p == StatementRowProblem.badDate
          ? ImportRowProblem.badDate
          : ImportRowProblem.badAmount;
      byProblem.update(mapped, (c) => c + n, ifAbsent: () => n);
    });
    // Flagged rows without a decision are reported under their own kinds
    // (a dry run), so the preview can show how many need the user.
    var pending = 0;
    for (final r in parsed.review) {
      if (decisions[r.number] != null) continue;
      pending++;
      final kind = r.review == StatementReviewReason.balanceMismatch
          ? ImportRowProblem.balanceMismatch
          : ImportRowProblem.directionUnknown;
      byProblem.update(kind, (c) => c + 1, ifAbsent: () => 1);
    }
    return ImportSummary(
      totalRows: parsed.totalRows,
      imported: imported,
      duplicates: duplicates,
      invalid: parsed.invalid,
      invalidByProblem: byProblem,
      invalidRows: parsed.invalidRows,
      earliest: earliest,
      latest: latest,
      needsReview: pending,
      duplicateRows: duplicateRows,
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
    // ignore: no_unmasked_amount - duplicate-detection key, never shown
    return '${d.code}|${s.minor}|${s.currency}';
  }
}
