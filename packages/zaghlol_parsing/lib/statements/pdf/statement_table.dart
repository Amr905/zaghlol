// T-156: from positioned text to a table of cells. Pure Dart.
//
// 1. Fragments become lines (same page, vertical distance within a small
//    tolerance), and neighbouring fragments of a line become cells.
// 2. Column edges come from, in order: a saved template, a recognised header
//    line (Date / Debit / Credit / Balance, English or Egyptian Arabic), or
//    the gaps in the data lines themselves.
// 3. A line whose date cell parses is a row; a following line with no date
//    and text only in one column is a continuation (wrapped description).
//
// Nothing here is bank-specific. Statement text is never logged.

import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency;

import '../../normalize/text_normalizer.dart';
import 'pdf_text_types.dart';
import 'statement_columns.dart';
import 'statement_dates.dart';

/// Most lines and fragments read from one file (a hostile PDF cannot make
/// the reader allocate without bound).
const int maxStatementFragments = 200000;

final class StatementCell {
  const StatementCell(this.text, this.x0, this.x1);
  final String text;
  final int x0;
  final int x1;
  int get center => (x0 + x1) ~/ 2;

  @override
  String toString() => 'StatementCell';
}

final class StatementLine {
  const StatementLine(this.page, this.y, this.cells);
  final int page;
  final int y;
  final List<StatementCell> cells;

  @override
  String toString() => 'StatementLine';
}

final RegExp _arabic = RegExp(r'[؀-ۿ]');

/// Groups fragments into lines of cells. Fragments closer than [mergeGap]
/// permille are one cell (Arabic cells are joined right to left).
List<StatementLine> groupStatementLines(
  List<PdfTextFragment> fragments, {
  int yTolerance = 3,
  int mergeGap = 12,
}) {
  final frags = fragments.length > maxStatementFragments
      ? fragments.sublist(0, maxStatementFragments)
      : [...fragments];
  frags.removeWhere((f) => normalizeText(f.text).isEmpty);
  frags.sort((a, b) {
    final p = a.page.compareTo(b.page);
    return p != 0 ? p : a.y.compareTo(b.y);
  });
  final lines = <StatementLine>[];
  var i = 0;
  while (i < frags.length) {
    final first = frags[i];
    final group = <PdfTextFragment>[first];
    var j = i + 1;
    while (j < frags.length &&
        frags[j].page == first.page &&
        (frags[j].y - first.y).abs() <= yTolerance) {
      group.add(frags[j]);
      j++;
    }
    i = j;
    group.sort((a, b) => a.x0.compareTo(b.x0));
    final cells = <StatementCell>[];
    var run = <PdfTextFragment>[group.first];
    void flush() {
      final texts = [for (final f in run) normalizeText(f.text)];
      final rtl =
          run.where((f) => _arabic.hasMatch(f.text)).length * 2 > run.length;
      cells.add(
        StatementCell(
          (rtl ? texts.reversed : texts).join(' '),
          run.first.x0,
          run.map((f) => f.x1).reduce((a, b) => a > b ? a : b),
        ),
      );
    }

    for (var k = 1; k < group.length; k++) {
      if (group[k].x0 - run.last.x1 <= mergeGap) {
        run.add(group[k]);
      } else {
        flush();
        run = [group[k]];
      }
    }
    flush();
    lines.add(StatementLine(first.page, first.y, cells));
  }
  return lines;
}

const Map<StatementColumnRole, List<String>> _headerWords = {
  StatementColumnRole.debit: [
    'debit',
    'withdrawal',
    'withdrawals',
    'dr',
    'مدين',
    'سحب',
    'المسحوبات',
    'منصرف',
    'المنصرف',
  ],
  StatementColumnRole.credit: [
    'credit',
    'deposit',
    'deposits',
    'cr',
    'دائن',
    'ايداع',
    'الايداع',
    'المودع',
    'المقبوضات',
  ],
  StatementColumnRole.balance: ['balance', 'الرصيد', 'رصيد'],
  StatementColumnRole.amount: ['amount', 'المبلغ', 'مبلغ', 'القيمه', 'قيمه'],
  StatementColumnRole.description: [
    'description',
    'details',
    'narrative',
    'particulars',
    'transaction',
    'البيان',
    'التفاصيل',
    'الوصف',
    'شرح',
    'بيان',
  ],
  StatementColumnRole.date: ['date', 'تاريخ', 'التاريخ'],
};

final Map<StatementColumnRole, List<String>> _words = {
  for (final e in _headerWords.entries)
    e.key: [for (final w in e.value) foldKey(w)],
};

StatementColumnRole? _headerRole(String text) {
  final tokens = foldKey(text).split(RegExp(r'[^a-z؀-ۿ]+'));
  for (final role in _words.keys) {
    final words = _words[role]!;
    if (tokens.any(words.contains)) return role;
  }
  return null;
}

/// A recognised header line.
final class StatementHeader {
  const StatementHeader(this.lineIndex, this.cuts, this.roles, this.texts);
  final int lineIndex;
  final List<int> cuts;
  final List<StatementColumnRole> roles;
  final List<String> texts;
}

/// Finds the first line that names a date column and at least one money
/// column. Only the first column of each role keeps it (a second "Date",
/// such as a value date, is ignored).
StatementHeader? detectStatementHeader(List<StatementLine> lines) {
  for (var li = 0; li < lines.length; li++) {
    final cells = lines[li].cells;
    if (cells.length < 3) continue;
    final roles = <StatementColumnRole>[];
    final seen = <StatementColumnRole>{};
    for (final c in cells) {
      final r = _headerRole(c.text);
      if (r == null || !seen.add(r)) {
        roles.add(StatementColumnRole.ignore);
      } else {
        roles.add(r);
      }
    }
    final hasDate = seen.contains(StatementColumnRole.date);
    final hasMoney =
        seen.contains(StatementColumnRole.amount) ||
        seen.contains(StatementColumnRole.debit) ||
        seen.contains(StatementColumnRole.credit);
    if (!hasDate || !hasMoney) continue;
    final cuts = <int>[
      for (var k = 0; k + 1 < cells.length; k++)
        (cells[k].x1 + cells[k + 1].x0) ~/ 2,
    ];
    return StatementHeader(li, cuts, roles, [for (final c in cells) c.text]);
  }
  return null;
}

final class StatementRawRow {
  const StatementRawRow(this.cells, {this.continuation = false});

  /// One string per column (empty when nothing is there).
  final List<String> cells;

  /// A wrapped line of the previous row's description.
  final bool continuation;

  @override
  String toString() => 'StatementRawRow';
}

final class StatementTable {
  const StatementTable({
    required this.cutPoints,
    required this.rows,
    required this.suggestedRoles,
    required this.confident,
    this.headerTexts = const [],
  });

  final List<int> cutPoints;
  final List<StatementRawRow> rows;

  /// A proposal for the mapping step; the user confirms or changes it.
  final List<StatementColumnRole> suggestedRoles;

  /// True when a saved template or a recognised header gave a valid mapping,
  /// so the user need not be asked.
  final bool confident;

  /// Header words per column when a header was found (shown in the mapping
  /// step to help the user).
  final List<String> headerTexts;

  int get columnCount => cutPoints.length + 1;

  @override
  String toString() => 'StatementTable';
}

int _columnOf(List<int> cuts, int x) {
  var i = 0;
  while (i < cuts.length && x >= cuts[i]) {
    i++;
  }
  return i;
}

List<String> _assign(StatementLine line, List<int> cuts) {
  final out = List<String>.filled(cuts.length + 1, '');
  for (final c in line.cells) {
    final k = _columnOf(cuts, c.center);
    out[k] = out[k].isEmpty ? c.text : '${out[k]} ${c.text}';
  }
  return out;
}

bool _isDateCell(String t, bool dayFirst) =>
    parseStatementDate(t, dayFirst: dayFirst) != null;

/// Data lines with no header: a date at either edge of the line.
bool _looksLikeDataLine(StatementLine l, bool dayFirst) {
  if (l.cells.length < 3) return false;
  return _isDateCell(l.cells.first.text, dayFirst) ||
      _isDateCell(l.cells.last.text, dayFirst);
}

/// Column edges from the gaps in the data lines: the union of the cells'
/// x ranges gives the column bands; edges sit midway between bands.
List<int> _inferCuts(List<StatementLine> data) {
  final spans = <(int, int)>[
    for (final l in data)
      for (final c in l.cells) (c.x0, c.x1),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final bands = <(int, int)>[];
  for (final s in spans) {
    if (bands.isNotEmpty && s.$1 <= bands.last.$2) {
      final last = bands.removeLast();
      bands.add((last.$1, s.$2 > last.$2 ? s.$2 : last.$2));
    } else {
      bands.add(s);
    }
  }
  return [
    for (var k = 0; k + 1 < bands.length; k++)
      (bands[k].$2 + bands[k + 1].$1) ~/ 2,
  ];
}

final RegExp _moneyShape = RegExp(r'^[\-(−]?\d[\d.,]*\)?-?(?:\s?(?:dr|cr))?$');

bool _isNumeric(String t) => _moneyShape.hasMatch(foldKey(t));

List<StatementColumnRole> _suggest(
  List<List<String>> body,
  int columns,
  bool dayFirst,
) {
  final roles = List<StatementColumnRole>.filled(
    columns,
    StatementColumnRole.ignore,
  );
  if (body.isEmpty) return roles;
  int frac(int c, bool Function(String) test) {
    final cells = [
      for (final r in body)
        if (r[c].isNotEmpty) r[c],
    ];
    if (cells.isEmpty) return 0;
    return cells.where(test).length * 100 ~/ cells.length;
  }

  var dateCol = -1;
  for (var c = 0; c < columns; c++) {
    if (frac(c, (t) => _isDateCell(t, dayFirst)) >= 80) {
      dateCol = c;
      break;
    }
  }
  final numeric = <int>[];
  var descCol = -1;
  var bestLen = -1;
  for (var c = 0; c < columns; c++) {
    if (c == dateCol) continue;
    final nonEmpty = body.where((r) => r[c].isNotEmpty).length;
    if (nonEmpty == 0) continue;
    if (frac(c, _isNumeric) >= 90) {
      numeric.add(c);
    } else {
      final avg = body.fold<int>(0, (a, r) => a + r[c].length) ~/ body.length;
      if (avg > bestLen) {
        bestLen = avg;
        descCol = c;
      }
    }
  }
  if (dateCol >= 0) roles[dateCol] = StatementColumnRole.date;
  if (descCol >= 0) roles[descCol] = StatementColumnRole.description;
  if (numeric.length == 1) {
    roles[numeric[0]] = StatementColumnRole.amount;
  } else if (numeric.length == 2) {
    roles[numeric[0]] = StatementColumnRole.amount;
    roles[numeric[1]] = StatementColumnRole.balance;
  } else if (numeric.length >= 3) {
    roles[numeric[0]] = StatementColumnRole.debit;
    roles[numeric[1]] = StatementColumnRole.credit;
    roles[numeric[2]] = StatementColumnRole.balance;
  }
  return roles;
}

/// Reads the table out of [fragments].
///
/// With a [template] its column edges are used and the result is confident.
/// Otherwise a header line is looked for, then the data lines' own gaps.
StatementTable buildStatementTable(
  List<PdfTextFragment> fragments, {
  StatementTemplate? template,
  bool dayFirst = true,
}) {
  final lines = groupStatementLines(fragments);
  final dayFirstEff = template?.mapping.dayFirst ?? dayFirst;
  List<int> cuts;
  var confident = false;
  var headerLine = -1;
  var headerTexts = const <String>[];
  List<StatementColumnRole>? headerRoles;
  if (template != null) {
    cuts = template.cutPoints;
    confident = true;
  } else {
    final h = detectStatementHeader(lines);
    if (h != null) {
      cuts = h.cuts;
      headerLine = h.lineIndex;
      headerTexts = h.texts;
      headerRoles = h.roles;
    } else {
      cuts = _inferCuts([
        for (final l in lines)
          if (_looksLikeDataLine(l, dayFirstEff)) l,
      ]);
    }
  }
  if (cuts.isEmpty) {
    return const StatementTable(
      cutPoints: [],
      rows: [],
      suggestedRoles: [],
      confident: false,
    );
  }

  final columns = cuts.length + 1;
  // Which column holds the date: from the template or header when known,
  // else the column that most lines have a date in.
  int? dateCol;
  if (template != null) {
    dateCol = template.mapping.indexOf(StatementColumnRole.date);
  } else if (headerRoles != null) {
    dateCol = headerRoles.indexOf(StatementColumnRole.date);
  }
  if (dateCol == null || dateCol < 0) {
    final votes = List<int>.filled(columns, 0);
    for (final l in lines) {
      final row = _assign(l, cuts);
      for (var c = 0; c < columns; c++) {
        if (_isDateCell(row[c], dayFirstEff)) votes[c]++;
      }
    }
    var best = 0;
    for (var c = 1; c < columns; c++) {
      if (votes[c] > votes[best]) best = c;
    }
    dateCol = best;
  }

  final rows = <StatementRawRow>[];
  final pitches = <int>[];
  StatementLine? prevData;
  var prevY = 0;
  for (var li = 0; li < lines.length; li++) {
    if (li <= headerLine) continue;
    final line = lines[li];
    final cells = _assign(line, cuts);
    if (_isDateCell(cells[dateCol], dayFirstEff)) {
      if (prevData != null && prevData.page == line.page) {
        pitches.add(line.y - prevData.y);
      }
      rows.add(StatementRawRow(cells));
      prevData = line;
      prevY = line.y;
    } else if (prevData != null && prevData.page == line.page) {
      final nonEmpty = cells.where((c) => c.isNotEmpty).length;
      final limit = pitches.isEmpty
          ? 25
          : (([...pitches]..sort())[pitches.length ~/ 2]) * 8 ~/ 5;
      if (nonEmpty == 1 && line.y - prevY <= limit) {
        rows.add(StatementRawRow(cells, continuation: true));
        prevY = line.y;
      }
    }
  }

  final body = [
    for (final r in rows)
      if (!r.continuation) r.cells,
  ];
  var roles = _suggest(body, columns, dayFirstEff);
  if (template != null) {
    roles = template.mapping.roles;
  } else if (headerRoles != null) {
    roles = headerRoles;
    // A header without a description column still reads: take the
    // suggestion's description column.
    if (!roles.contains(StatementColumnRole.description)) {
      final s = _suggest(body, columns, dayFirstEff);
      final d = s.indexOf(StatementColumnRole.description);
      if (d >= 0 && roles[d] == StatementColumnRole.ignore) {
        roles = [...roles]..[d] = StatementColumnRole.description;
      }
    }
    confident = StatementMapping(
      roles: roles,
      currency: Currency.of('EGP'),
    ).isValid;
  }
  return StatementTable(
    cutPoints: cuts,
    rows: rows,
    suggestedRoles: roles,
    confident: confident,
    headerTexts: headerTexts,
  );
}
