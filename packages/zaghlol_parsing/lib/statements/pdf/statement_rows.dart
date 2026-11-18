// T-156: table rows to statement rows with exact money. Pure Dart.
//
// Amounts go through [parseAmount] (integer minor units, never a double) in
// the mapping's currency; the sign comes from the column (debit = out,
// credit = in) or, in a single amount column, from `-`, `(...)`, a trailing
// `-`, `DR` / `CR` or `مدين` / `دائن`. Nothing is converted, summed or
// echoed: problems are counted by kind and row number only.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../normalize/amount_parser.dart';
import '../../normalize/text_normalizer.dart';
import 'statement_columns.dart';
import 'statement_dates.dart';
import 'statement_table.dart';

enum StatementRowProblem { badDate, badAmount, noAmount, bothAmounts }

final class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.isExpense,
    required this.amount,
    this.balance,
  });

  final StatementDate date;
  final String description;

  /// True for money out (debit).
  final bool isExpense;

  /// Always positive; the direction is [isExpense].
  final Money amount;

  /// The running balance printed on the row, when the mapping has one.
  final Money? balance;

  @override
  String toString() => 'StatementRow';
}

/// Most rows one statement may hold and most invalid row numbers listed.
const int maxStatementRows = 20000;
const int maxListedInvalidRows = 20;
const int maxStatementDescriptionRunes = 200;

final class StatementParseResult {
  const StatementParseResult({
    required this.rows,
    required this.problems,
    required this.invalidRows,
    required this.totalRows,
  });

  final List<StatementRow> rows;
  final Map<StatementRowProblem, int> problems;

  /// 1-based numbers of the first invalid rows (continuations not counted).
  final List<int> invalidRows;
  final int totalRows;

  int get invalid => problems.values.fold(0, (a, b) => a + b);

  @override
  String toString() => 'StatementParseResult';
}

/// A parsed amount cell: magnitude plus the sign the text carried
/// (`null` = no sign in the text).
typedef SignedAmount = ({Money amount, bool? negative});

final RegExp _drCr = RegExp(r'\s*(dr|cr|مدين|دائن)$');
final RegExp _wrap = RegExp(r'^\((.*)\)$');

/// Parses one amount cell, or null when it is empty or not a number.
SignedAmount? parseStatementAmount(
  String cell, {
  required Currency currency,
  NumberLocale locale = NumberLocale.standard,
}) {
  var t = foldKey(cell).replaceAll('−', '-').trim();
  if (t.isEmpty) return null;
  bool? negative;
  final suffix = _drCr.firstMatch(t);
  if (suffix != null) {
    final w = suffix.group(1)!;
    negative = w == 'dr' || w == 'مدين';
    t = t.substring(0, suffix.start).trim();
  }
  final wrapped = _wrap.firstMatch(t);
  if (wrapped != null) {
    negative = true;
    t = wrapped.group(1)!.trim();
  }
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1).trim();
  } else if (t.startsWith('+')) {
    t = t.substring(1).trim();
  }
  if (t.endsWith('-')) {
    negative = true;
    t = t.substring(0, t.length - 1).trim();
  }
  final r = parseAmount(t, currency: currency, locale: locale);
  return switch (r) {
    Ok(:final value) => (amount: value, negative: negative),
    Err() => null,
  };
}

String _clean(String s) {
  final t = normalizeText(s);
  final runes = t.runes.toList();
  return runes.length <= maxStatementDescriptionRunes
      ? t
      : String.fromCharCodes(runes.take(maxStatementDescriptionRunes));
}

StatementParseResult parseStatementRows(
  StatementTable table,
  StatementMapping mapping,
) {
  final problems = <StatementRowProblem, int>{};
  final invalidRows = <int>[];
  final rows = <StatementRow>[];
  if (!mapping.isValid || mapping.roles.length != table.columnCount) {
    return const StatementParseResult(
      rows: [],
      problems: {},
      invalidRows: [],
      totalRows: 0,
    );
  }
  final dateI = mapping.indexOf(StatementColumnRole.date);
  final descI = mapping.indexOf(StatementColumnRole.description);
  final debitI = mapping.indexOf(StatementColumnRole.debit);
  final creditI = mapping.indexOf(StatementColumnRole.credit);
  final amountI = mapping.indexOf(StatementColumnRole.amount);
  final balanceI = mapping.indexOf(StatementColumnRole.balance);
  final cur = mapping.currency;
  final loc = mapping.numberLocale;

  // Continuations first: fold wrapped description lines into their row.
  final descriptions = <int, String>{};
  var n = -1;
  for (var i = 0; i < table.rows.length; i++) {
    final r = table.rows[i];
    if (r.continuation) {
      if (n >= 0 && r.cells[descI].isNotEmpty) {
        descriptions[n] = '${descriptions[n]} ${r.cells[descI]}';
      }
    } else {
      n = i;
      descriptions[n] = r.cells[descI];
    }
  }

  var number = 0;
  for (var i = 0; i < table.rows.length; i++) {
    final r = table.rows[i];
    if (r.continuation) continue;
    number++;
    if (number > maxStatementRows) break;
    void bad(StatementRowProblem p) {
      problems.update(p, (c) => c + 1, ifAbsent: () => 1);
      if (invalidRows.length < maxListedInvalidRows) invalidRows.add(number);
    }

    final date = parseStatementDate(r.cells[dateI], dayFirst: mapping.dayFirst);
    if (date == null) {
      bad(StatementRowProblem.badDate);
      continue;
    }
    bool? expense;
    Money? amount;
    var failed = false;
    if (amountI >= 0) {
      final a = parseStatementAmount(
        r.cells[amountI],
        currency: cur,
        locale: loc,
      );
      if (a == null) {
        bad(
          r.cells[amountI].trim().isEmpty
              ? StatementRowProblem.noAmount
              : StatementRowProblem.badAmount,
        );
        continue;
      }
      amount = a.amount;
      expense = a.negative ?? false;
    } else {
      Money? debit;
      Money? credit;
      if (debitI >= 0 && r.cells[debitI].trim().isNotEmpty) {
        final a = parseStatementAmount(
          r.cells[debitI],
          currency: cur,
          locale: loc,
        );
        if (a == null) failed = true;
        debit = a?.amount;
      }
      if (creditI >= 0 && r.cells[creditI].trim().isNotEmpty) {
        final a = parseStatementAmount(
          r.cells[creditI],
          currency: cur,
          locale: loc,
        );
        if (a == null) failed = true;
        credit = a?.amount;
      }
      if (failed) {
        bad(StatementRowProblem.badAmount);
        continue;
      }
      // A printed 0.00 in the unused column is not a second amount.
      if (debit != null && debit.minor == 0) debit = null;
      if (credit != null && credit.minor == 0) credit = null;
      if (debit != null && credit != null) {
        bad(StatementRowProblem.bothAmounts);
        continue;
      }
      if (debit == null && credit == null) {
        bad(StatementRowProblem.noAmount);
        continue;
      }
      expense = debit != null;
      amount = debit ?? credit;
    }
    if (amount!.minor == 0) {
      bad(StatementRowProblem.noAmount);
      continue;
    }
    Money? balance;
    if (balanceI >= 0) {
      final b = parseStatementAmount(
        r.cells[balanceI],
        currency: cur,
        locale: loc,
      );
      if (b != null) {
        balance = b.negative ?? false ? -b.amount : b.amount;
      }
    }
    rows.add(
      StatementRow(
        date: date,
        description: _clean(descriptions[i] ?? ''),
        isExpense: expense,
        amount: amount.minor < 0 ? -amount : amount,
        balance: balance,
      ),
    );
  }
  return StatementParseResult(
    rows: rows,
    problems: problems,
    invalidRows: invalidRows,
    totalRows: number > maxStatementRows ? maxStatementRows : number,
  );
}
