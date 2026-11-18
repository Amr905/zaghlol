// T-156: table rows to statement rows with exact money. Pure Dart.
//
// Amounts go through [parseAmount] (integer minor units, never a double) in
// the mapping's currency; the sign comes from the column (debit = out,
// credit = in) or, in a single amount column, from `-`, `(...)`, a trailing
// `-`, `DR` / `CR` or `مدين` / `دائن`. Nothing is converted, summed or
// echoed: problems are counted by kind and row number only.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../normalize/amount_parser.dart';
import '../../normalize/currency_markers.dart';
import '../../normalize/text_normalizer.dart';
import 'statement_columns.dart';
import 'statement_dates.dart';
import 'statement_table.dart';

enum StatementRowProblem {
  badDate,
  badAmount,
  noAmount,
  bothAmounts,

  /// The running balance does not equal the previous balance plus this
  /// row's credit minus its debit. The row is not imported.
  balanceMismatch,
}

final class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.isExpense,
    required this.amount,
    this.balance,
    this.balanceChecked = false,
  });

  final StatementDate date;
  final String description;

  /// True for money out (debit).
  final bool isExpense;

  /// Always positive; the direction is [isExpense].
  final Money amount;

  /// The running balance printed on the row, when the mapping has one.
  final Money? balance;

  /// True when the running balance confirmed this row (previous balance
  /// plus the row equals the printed balance).
  final bool balanceChecked;

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
    this.balanceChecked = 0,
    this.closingMatches,
  });

  final List<StatementRow> rows;

  /// Rows the running balance confirmed.
  final int balanceChecked;

  /// Whether the last printed balance equals the statement's closing
  /// balance; null when either is missing.
  final bool? closingMatches;
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
final RegExp _arabicCurrency = RegExp(r'ج\.\s?م\.?|جنيها?ا?|l\.\s?e\.?|\ble\b');
final RegExp _isoWord = RegExp(r'(?<![a-z])[a-z]{3}(?![a-z])');

/// Removes currency symbols and names (`$`, `£`, `EGP`, `ج.م`, `جنيه`) from
/// an amount cell. Only known markers go; other text stays and fails the
/// number check.
String _stripCurrency(String t) {
  var out = t;
  for (final sym in currencySymbols.keys) {
    out = out.replaceAll(sym, ' ');
  }
  out = out.replaceAll(_arabicCurrency, ' ');
  out = out.replaceAllMapped(
    _isoWord,
    (m) =>
        Currency.tryOf(m.group(0)!.toUpperCase()) != null ? ' ' : m.group(0)!,
  );
  return out.trim();
}

final RegExp _wrap = RegExp(r'^\((.*)\)$');

/// Parses one amount cell, or null when it is empty or not a number.
SignedAmount? parseStatementAmount(
  String cell, {
  required Currency currency,
  NumberLocale locale = NumberLocale.standard,
}) {
  var t = _stripCurrency(foldKey(cell).replaceAll('−', '-'))
      .replaceAll(RegExp(r'\s+'), ' ');
  t = t.trim();
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
  // `.26` and `,26` (no leading zero) are 0.26.
  final decimal = locale == NumberLocale.standard ? '.' : ',';
  if (t.startsWith(decimal)) t = '0$t';
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

/// One table row after parsing, before the balance check.
class _Entry {
  _Entry(this.number);
  final int number;
  StatementRow? row;
  StatementRowProblem? problem;

  /// The printed running balance, kept even when the row itself is invalid
  /// so that the chain can resume after it.
  Money? printed;

  /// The amount column carried no sign, so direction may come from balances.
  bool unsigned = false;
  bool? derivedExpense;
  bool verified = false;
  bool mismatch = false;
}

/// Checks [entries] (in the given order) against the running balance: each
/// printed balance must equal the previous one plus credit minus debit.
/// Fills `mismatch`, `verified` and `derivedExpense`; returns the number of
/// mismatches. [start] is the balance before the first row, when known.
int _chain(List<_Entry> entries, Money? start) {
  var running = start;
  var bad = 0;
  for (final e in entries) {
    e
      ..mismatch = false
      ..verified = false
      ..derivedExpense = null;
    final row = e.row;
    Money? signed;
    if (row != null) {
      final printed = e.printed;
      if (e.unsigned) {
        if (running != null && printed != null) {
          final delta = printed - running;
          if (delta == row.amount) {
            e.derivedExpense = false;
            e.verified = true;
          } else if (delta == -row.amount) {
            e.derivedExpense = true;
            e.verified = true;
          } else {
            e.mismatch = true;
            bad++;
          }
        } else if (running != null && printed == null) {
          // Direction unknown and nothing to derive it from.
        }
        final ex = e.derivedExpense;
        if (ex != null) signed = ex ? -row.amount : row.amount;
      } else {
        signed = row.isExpense ? -row.amount : row.amount;
        if (running != null && printed != null) {
          if (printed - running == signed) {
            e.verified = true;
          } else {
            e.mismatch = true;
            bad++;
          }
        }
      }
    }
    final p = e.printed;
    if (p != null) {
      running = p;
    } else if (running != null && signed != null) {
      running = running + signed;
    } else {
      running = null;
    }
  }
  return bad;
}

StatementParseResult parseStatementRows(
  StatementTable table,
  StatementMapping mapping,
) {
  final problems = <StatementRowProblem, int>{};
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

  Money? balanceOf(String cell) {
    final b = parseStatementAmount(cell, currency: cur, locale: loc);
    if (b == null) return null;
    return b.negative ?? false ? -b.amount : b.amount;
  }

  final entries = <_Entry>[];
  var number = 0;
  for (var i = 0; i < table.rows.length; i++) {
    final r = table.rows[i];
    if (r.continuation) continue;
    number++;
    if (number > maxStatementRows) break;
    final e = _Entry(number);
    entries.add(e);
    if (balanceI >= 0) e.printed = balanceOf(r.cells[balanceI]);

    final date = parseStatementDate(r.cells[dateI], dayFirst: mapping.dayFirst);
    if (date == null) {
      e.problem = StatementRowProblem.badDate;
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
        e.problem = r.cells[amountI].trim().isEmpty
            ? StatementRowProblem.noAmount
            : StatementRowProblem.badAmount;
        continue;
      }
      amount = a.amount;
      expense = a.negative ?? false;
      e.unsigned = a.negative == null && balanceI >= 0;
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
        e.problem = StatementRowProblem.badAmount;
        continue;
      }
      // A printed 0.00 in the unused column is not a second amount.
      if (debit != null && debit.minor == 0) debit = null;
      if (credit != null && credit.minor == 0) credit = null;
      if (debit != null && credit != null) {
        e.problem = StatementRowProblem.bothAmounts;
        continue;
      }
      if (debit == null && credit == null) {
        e.problem = StatementRowProblem.noAmount;
        continue;
      }
      expense = debit != null;
      amount = debit ?? credit;
    }
    if (amount!.minor == 0) {
      e.problem = StatementRowProblem.noAmount;
      continue;
    }
    e.row = StatementRow(
      date: date,
      description: _clean(descriptions[i] ?? ''),
      isExpense: expense,
      amount: amount.minor < 0 ? -amount : amount,
      balance: e.printed,
    );
  }

  // Running-balance check. Statements are normally oldest first; a list
  // that is newest first fits the chain better in reverse, so both orders
  // are tried and the one with fewer mismatches wins (forward on a tie).
  var checkedCount = 0;
  bool? closing;
  if (balanceI >= 0) {
    final opening = table.openingBalance == null
        ? null
        : balanceOf(table.openingBalance!);
    final forward = _chain(entries, opening);
    var chrono = entries;
    if (forward > 0) {
      final rev = entries.reversed.toList();
      if (_chain(rev, null) < forward) {
        chrono = rev;
      } else {
        _chain(entries, opening);
      }
    }
    for (final e in entries) {
      final row = e.row;
      if (row == null) continue;
      if (e.mismatch) {
        e.row = null;
        e.problem = StatementRowProblem.balanceMismatch;
        continue;
      }
      if (e.verified) checkedCount++;
      final ex = e.derivedExpense;
      e.row = StatementRow(
        date: row.date,
        description: row.description,
        isExpense: ex ?? row.isExpense,
        amount: row.amount,
        balance: row.balance,
        balanceChecked: e.verified,
      );
    }
    final lastPrinted = chrono.reversed
        .map((e) => e.printed)
        .firstWhere((b) => b != null, orElse: () => null);
    final c = table.closingBalance == null
        ? null
        : balanceOf(table.closingBalance!);
    if (lastPrinted != null && c != null) closing = c == lastPrinted;
  }
  return _finish(entries, problems, rows, number, checkedCount, closing);
}

StatementParseResult _finish(
  List<_Entry> entries,
  Map<StatementRowProblem, int> problems,
  List<StatementRow> rows,
  int number,
  int checked,
  bool? closingMatches,
) {
  final invalid = <int>[];
  for (final e in entries) {
    final p = e.problem;
    if (p != null) {
      problems.update(p, (c) => c + 1, ifAbsent: () => 1);
      if (invalid.length < maxListedInvalidRows) invalid.add(e.number);
    } else if (e.row != null) {
      rows.add(e.row!);
    }
  }
  return StatementParseResult(
    rows: rows,
    problems: problems,
    invalidRows: invalid,
    totalRows: number > maxStatementRows ? maxStatementRows : number,
    balanceChecked: checked,
    closingMatches: closingMatches,
  );
}
