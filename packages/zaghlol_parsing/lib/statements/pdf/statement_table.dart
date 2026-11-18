// T-156: from positioned text to a table of cells. Pure Dart.
//
// 0. A statement may hold several tables (daily activity, then the same
//    transactions grouped by type, a list of cheques). Each recognised header
//    starts a section; sections with the same columns are one table, and the
//    table with a Balance column is preferred over the others, which list the
//    same transactions (T-156b).
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

import '../../normalize/currency_markers.dart';
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
      if (!group[k].breakBefore && group[k].x0 - run.last.x1 <= mergeGap) {
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
    'debits',
    'withdrawal',
    'withdrawals',
    'paid out',
    'money out',
    'amount out',
    'payments',
    'dr',
    'مدين',
    'سحب',
    'سحوبات',
    'المسحوبات',
    'منصرف',
    'المنصرف',
  ],
  StatementColumnRole.credit: [
    'credit',
    'credits',
    'deposit',
    'deposits',
    'paid in',
    'money in',
    'amount in',
    'receipts',
    'cr',
    'دائن',
    'ايداع',
    'ايداعات',
    'الايداع',
    'المودع',
    'المقبوضات',
  ],
  StatementColumnRole.balance: ['balance', 'الرصيد', 'رصيد'],
  StatementColumnRole.amount: ['amount', 'المبلغ', 'مبلغ', 'القيمه', 'قيمه'],
  StatementColumnRole.description: [
    'description',
    'details',
    'detail',
    'narrative',
    'particulars',
    'transaction',
    'remarks',
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

final RegExp _typeWord = RegExp(r'(^|\s)(type|نوع|النوع)(\s|$)');

StatementColumnRole? _headerRole(String text) {
  final tokens = foldKey(text)
      .split(RegExp(r'[^a-z؀-ۿ]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;
  final joined = tokens.join(' ');
  // "Date" wins over "Transaction Date"; "Payment Type" is not a detail.
  if (tokens.contains('date') ||
      tokens.contains('تاريخ') ||
      tokens.contains(foldKey('التاريخ'))) {
    return StatementColumnRole.date;
  }
  if (_typeWord.hasMatch(joined)) return null;
  // Phrases first ("paid in"), then single words.
  for (final role in _words.keys) {
    for (final w in _words[role]!) {
      if (w.contains(' ') && joined.contains(w)) return role;
    }
  }
  for (final role in _words.keys) {
    final words = _words[role]!;
    if (tokens.any(words.contains)) return role;
  }
  return null;
}

/// A recognised header line.
final class StatementHeader {
  const StatementHeader(
    this.lineIndex,
    this.cuts,
    this.roles,
    this.texts, [
    this.spans = const [],
  ]);
  final int lineIndex;
  final List<int> cuts;
  final List<StatementColumnRole> roles;
  final List<String> texts;

  /// x range (x0, x1) of each header cell.
  final List<(int, int)> spans;
}

StatementHeader? _headerOf(List<StatementLine> lines, int li) {
  final cells = lines[li].cells;
  if (cells.length < 3) return null;
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
  if (!hasDate || !hasMoney) return null;
  // Most cells of a header are header words: a data line that happens to
  // name a date and an amount is not a header.
  final named = roles.where((r) => r != StatementColumnRole.ignore).length;
  final ignorable = cells
      .where((c) => _headerRole(c.text) == null && c.text.length <= 40)
      .length;
  if (named + ignorable < cells.length - 1) return null;
  final cuts = <int>[
    for (var k = 0; k + 1 < cells.length; k++)
      (cells[k].x1 + cells[k + 1].x0) ~/ 2,
  ];
  return StatementHeader(
    li,
    cuts,
    roles,
    [for (final c in cells) c.text],
    [for (final c in cells) (c.x0, c.x1)],
  );
}

/// Every line that names a date column and at least one money column. Only
/// the first column of each role keeps it (a second "Date", such as a value
/// date, is ignored).
List<StatementHeader> detectStatementHeaders(List<StatementLine> lines) {
  final out = <StatementHeader>[];
  for (var li = 0; li < lines.length; li++) {
    final h = _headerOf(lines, li);
    if (h != null) out.add(h);
  }
  return out;
}

/// The first header line, or null.
StatementHeader? detectStatementHeader(List<StatementLine> lines) {
  for (var li = 0; li < lines.length; li++) {
    final h = _headerOf(lines, li);
    if (h != null) return h;
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
    this.openingBalance,
    this.closingBalance,
    this.suggestedCurrency,
    this.dayFirst = true,
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

  /// The opening and closing balance printed outside the rows ("Balance
  /// Brought Forward", "Opening balance", "Ending balance"), as cell text.
  /// The first row's balance is checked against the opening one.
  final String? openingBalance;
  final String? closingBalance;

  /// A currency the statement names (`$` USD, `£` GBP, `EGP`, `ج.م`), when
  /// exactly one appears. A proposal for the user to confirm: nothing is
  /// converted.
  final Currency? suggestedCurrency;

  /// Numeric dates are day first (true) or month first (false), read from
  /// the dates themselves, else the caller's default. Date cells of the rows
  /// are already rewritten to `yyyy-mm-dd`.
  final bool dayFirst;

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
    parseStatementDate(t, dayFirst: dayFirst) != null ||
    parsePartialStatementDate(t, dayFirst: dayFirst) != null;

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

// ---------------------------------------------------------------------------
// Sections, balances, currency, years.

final RegExp _endLine = RegExp(
  r'^[\-–—=*_~\s]{2,}.*[\-–—=*_~\s]{2,}$'
  r'|(^|\s)end of (transactions|statement|report|list|activity)'
  r'|^(total|totals|sub ?total|closing balance|ending balance|balance carried|carried forward)\b'
  r'|^(اجمالي|الاجمالي|المجموع|مجموع|نهايه|الرصيد الختامي|الرصيد النهائي)',
);
final RegExp _pageLine = RegExp(r'^(page|صفحه)\s*\d+(\s*(of|من|/)\s*\d+)?$');
final RegExp _openingLabel = RegExp(
  r'^(opening|beginning|previous|prior|starting) balance|brought forward'
  r'|balance b/?f\b|^(الرصيد )?(الافتتاحي|السابق|الابتدائي|المرحل)'
  r'|^رصيد (افتتاحي|سابق|اول المده)',
);
final RegExp _closingLabel = RegExp(
  r'^(closing|ending|final|new) balance|carried forward'
  r'|^(الرصيد )?(الختامي|النهائي)|^رصيد ختامي',
);
final RegExp _amountCell = RegExp(
  r'^[\-(−]?(?:[$£€]|[a-z]{3})?\s?[\-(−]?(?:\d[\d,.]*\d|\d|[.,]\d+)\)?-?(?:\s?(?:dr|cr))?$',
);
final RegExp _trailingDecimal = RegExp(
  r'[\-(]?[$£€]?\s?\d[\d,]*[.,]\d{1,3}\)?$',
);

String _lineText(StatementLine l) =>
    foldKey(l.cells.map((c) => c.text).join(' '));

/// Opening and closing balance from label + amount cells outside dated rows.
(String?, String?) _scanBalances(List<StatementLine> lines, bool dayFirst) {
  String? opening;
  String? closing;
  for (final l in lines) {
    if (l.cells.any((c) => _isDateCell(c.text, dayFirst))) continue;
    for (var i = 0; i < l.cells.length; i++) {
      final label = foldKey(l.cells[i].text);
      final isOpen = opening == null && _openingLabel.hasMatch(label);
      final isClose = closing == null && _closingLabel.hasMatch(label);
      if (!isOpen && !isClose) continue;
      String? value;
      for (var j = i + 1; j < l.cells.length && value == null; j++) {
        if (_amountCell.hasMatch(foldKey(l.cells[j].text))) {
          value = l.cells[j].text;
        }
      }
      if (value == null) {
        final m = _trailingDecimal.firstMatch(normalizeText(l.cells[i].text));
        if (m != null) value = m.group(0);
      }
      if (value == null) continue;
      if (isOpen) opening = value;
      if (isClose) closing = value;
      break;
    }
  }
  return (opening, closing);
}

const Map<String, String> _isoNames = {
  'egp': 'EGP',
  'usd': 'USD',
  'gbp': 'GBP',
  'eur': 'EUR',
  'sar': 'SAR',
  'aed': 'AED',
  'kwd': 'KWD',
  'qar': 'QAR',
  'bhd': 'BHD',
  'omr': 'OMR',
  'jod': 'JOD',
};
final RegExp _isoToken = RegExp(
  r'(?<![a-z])(egp|usd|gbp|eur|sar|aed|kwd|qar|bhd|omr|jod)(?![a-z])',
);
final RegExp _egpArabic = RegExp(r'ج\.\s?م|جنيه|\bl\.?e\.?\b');

/// The one currency a statement names, or null (none, or several).
Currency? _detectCurrency(List<StatementLine> lines) {
  final found = <String>{};
  var digits = 0;
  for (final l in lines) {
    for (final c in l.cells) {
      final t = foldKey(c.text);
      if (!RegExp(r'\d').hasMatch(t) && !_isoToken.hasMatch(t)) {
        if (_egpArabic.hasMatch(t)) found.add('EGP');
        continue;
      }
      if (digits++ > 5000) break;
      if (RegExp(r'\d').hasMatch(t)) {
        for (final e in currencySymbols.entries) {
          if (t.contains(e.key) && e.value.defaultCode != null) {
            found.add(e.value.defaultCode!);
          }
        }
        if (_egpArabic.hasMatch(t)) found.add('EGP');
      }
      for (final m in _isoToken.allMatches(t)) {
        found.add(_isoNames[m.group(1)!]!);
      }
    }
  }
  return found.length == 1 ? Currency.tryOf(found.single) : null;
}

final RegExp _fullDateText = RegExp(
  r'\d{1,4}[/\-.]\d{1,2}[/\-.]\d{1,4}'
  r'|\d{1,2}\s+[A-Za-z]+\.?,?\s+\d{4}'
  r'|[A-Za-z]+\.?\s+\d{1,2},?\s+\d{4}',
);

/// The latest full date printed anywhere (period, statement date), not far
/// in the future; else [today].
StatementDate _anchorDate(
  List<StatementLine> lines,
  bool dayFirst,
  DateTime today,
) {
  final limit = today.add(const Duration(days: 45));
  StatementDate? best;
  DateTime? bestAt;
  for (final l in lines) {
    for (final c in l.cells) {
      for (final m in _fullDateText.allMatches(normalizeText(c.text))) {
        final d = parseStatementDate(m.group(0)!, dayFirst: dayFirst);
        if (d == null) continue;
        final at = DateTime(d.year, d.month, d.day);
        if (at.isAfter(limit)) continue;
        if (bestAt == null || at.isAfter(bestAt)) {
          best = d;
          bestAt = at;
        }
      }
    }
  }
  return best ?? StatementDate(today.year, today.month, today.day);
}

typedef _Layout = ({
  List<int> cuts,
  List<StatementColumnRole> roles,
  List<String> texts,
});

final class _Section {
  _Section(this.layout, this.rows);
  final _Layout layout;
  final List<StatementRawRow> rows;
  int get dataRows => rows.where((r) => !r.continuation).length;
  bool get hasBalance => layout.roles.contains(StatementColumnRole.balance);
  String get signature => layout.roles.map((r) => r.name).join(',');
}

int _distance(int x, (int, int) band) =>
    x < band.$1 ? band.$1 - x : (x > band.$2 ? x - band.$2 : 0);

/// Column layout from a header: the column bands come from where the data
/// cells really are (a centred header over left-aligned text would put the
/// midpoint cuts in the wrong place), each header cell is matched to the
/// nearest band. When that match is not one-to-one the header's own
/// midpoints are used.
_Layout _layoutFromHeader(
  StatementHeader h,
  List<StatementLine> span,
  bool dayFirst,
) {
  final fallback = (cuts: h.cuts, roles: h.roles, texts: h.texts);
  final dateIdx = h.roles.indexOf(StatementColumnRole.date);
  if (dateIdx < 0 || h.spans.length != h.roles.length) return fallback;
  final ds = h.spans[dateIdx];
  final data = [
    for (final l in span)
      if (l.cells.any(
        (c) =>
            c.x1 >= ds.$1 - 60 &&
            c.x0 <= ds.$2 + 60 &&
            _isDateCell(c.text, dayFirst),
      ))
        l,
  ];
  final bands = _bands(data);
  if (bands.length < 2) return fallback;
  final owner = <int>[];
  for (final s in h.spans) {
    final center = (s.$1 + s.$2) ~/ 2;
    var best = 0;
    for (var j = 1; j < bands.length; j++) {
      if (_distance(center, bands[j]) < _distance(center, bands[best])) {
        best = j;
      }
    }
    owner.add(best);
  }
  if (owner.toSet().length != owner.length) return fallback;
  final roles = <StatementColumnRole>[];
  final texts = <String>[];
  final extent = <(int, int)>[];
  for (var j = 0; j < bands.length; j++) {
    final k = owner.indexOf(j);
    if (k >= 0) {
      roles.add(h.roles[k]);
      texts.add(h.texts[k]);
      extent.add(bands[j]);
    } else if (roles.isNotEmpty &&
        roles.last == StatementColumnRole.description) {
      // A second text cell of the description (reference, terminal): the
      // same column.
      extent[extent.length - 1] = (extent.last.$1, bands[j].$2);
    } else {
      roles.add(StatementColumnRole.ignore);
      texts.add('');
      extent.add(bands[j]);
    }
  }
  if (roles.length < 2) return fallback;
  return (
    cuts: [
      for (var k = 0; k + 1 < extent.length; k++)
        (extent[k].$2 + extent[k + 1].$1) ~/ 2,
    ],
    roles: roles,
    texts: texts,
  );
}

List<(int, int)> _bands(List<StatementLine> data) {
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
  return bands;
}

/// Rows of one section: lines in [from, to) with a date in the date column,
/// wrapped description lines, stopping at an end line ("--- End of
/// Transactions ---", "Total ...").
_Section _readSection(
  List<StatementLine> lines,
  int from,
  int to,
  _Layout layout,
  int? dateColumn,
  bool dayFirst,
) {
  final cuts = layout.cuts;
  final columns = cuts.length + 1;
  var dateCol = dateColumn ?? layout.roles.indexOf(StatementColumnRole.date);
  if (dateCol < 0) {
    final votes = List<int>.filled(columns, 0);
    for (var li = from; li < to; li++) {
      final row = _assign(lines[li], cuts);
      for (var c = 0; c < columns; c++) {
        if (_isDateCell(row[c], dayFirst)) votes[c]++;
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
  for (var li = from; li < to; li++) {
    final line = lines[li];
    final cells = _assign(line, cuts);
    if (_isDateCell(cells[dateCol], dayFirst)) {
      if (prevData != null && prevData.page == line.page) {
        pitches.add(line.y - prevData.y);
      }
      rows.add(StatementRawRow(cells));
      prevData = line;
      prevY = line.y;
      continue;
    }
    final text = _lineText(line);
    if (rows.isNotEmpty && _endLine.hasMatch(text)) break;
    if (_pageLine.hasMatch(text)) continue;
    if (prevData != null && prevData.page == line.page) {
      final nonEmpty = cells.where((c) => c.isNotEmpty).toList();
      final limit = pitches.isEmpty
          ? 25
          : (([...pitches]..sort())[pitches.length ~/ 2]) * 8 ~/ 5;
      if (nonEmpty.length == 1 &&
          !_isNumeric(nonEmpty.single) &&
          line.y - prevY <= limit) {
        rows.add(StatementRawRow(cells, continuation: true));
        prevY = line.y;
      }
    }
  }
  return _Section(layout, rows);
}

String _digitsKey(String t) {
  final d = t.replaceAll(RegExp(r'[^0-9]'), '');
  return d.replaceFirst(RegExp(r'^0+'), '');
}

Set<String> _tokens(String t) => {
  for (final w in foldKey(t).split(RegExp(r'[^a-z0-9؀-ۿ]+')))
    if (w.length > 1) w,
};

/// A key to compare two rows of different tables: the date text, the money
/// digits, and the description words.
({String date, String money, Set<String> words}) _rowKey(
  StatementRawRow r,
  List<StatementColumnRole> roles,
) {
  final money = StringBuffer();
  var desc = '';
  var date = '';
  for (var i = 0; i < roles.length; i++) {
    switch (roles[i]) {
      case StatementColumnRole.debit:
      case StatementColumnRole.credit:
      case StatementColumnRole.amount:
        money.write(_digitsKey(r.cells[i]));
        money.write('|');
      case StatementColumnRole.description:
        desc = r.cells[i];
      case StatementColumnRole.date:
        date = foldKey(r.cells[i]);
      case _:
        break;
    }
  }
  return (date: date, money: money.toString(), words: _tokens(desc));
}

bool _similar(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return true;
  final inter = a.intersection(b).length;
  final union = a.union(b).length;
  return inter * 100 >= union * 30;
}

/// True when [later] only repeats the rows of [earlier]: at least 80% of its
/// rows (two or more) have a row with the same date, amount and a similar
/// description.
bool _repeats(_Section later, List<_Section> earlier) {
  final rows = [
    for (final r in later.rows)
      if (!r.continuation) r,
  ];
  if (rows.length < 2) return false;
  final known = <({String date, String money, Set<String> words})>[
    for (final s in earlier)
      for (final r in s.rows)
        if (!r.continuation) _rowKey(r, s.layout.roles),
  ];
  var hit = 0;
  for (final r in rows) {
    final k = _rowKey(r, later.layout.roles);
    if (k.money == '|' || k.money.isEmpty) continue;
    if (known.any(
      (o) =>
          o.date == k.date && o.money == k.money && _similar(o.words, k.words),
    )) {
      hit++;
    }
  }
  return hit * 5 >= rows.length * 4;
}

/// Reads the table out of [fragments].
///
/// With a [template] its column edges are used and the result is confident.
/// Otherwise headers are looked for, then the data lines' own gaps.
/// [today] is the fallback end of a statement whose dates have no year.
StatementTable buildStatementTable(
  List<PdfTextFragment> fragments, {
  StatementTemplate? template,
  bool dayFirst = true,
  DateTime? today,
}) {
  const empty = StatementTable(
    cutPoints: [],
    rows: [],
    suggestedRoles: [],
    confident: false,
  );
  final lines = groupStatementLines(fragments);
  if (lines.isEmpty) return empty;

  var dayFirstEff = template?.mapping.dayFirst ?? dayFirst;
  if (template == null) {
    final detected = detectDayFirst([
      for (final l in lines)
        for (final c in l.cells) c.text,
    ]);
    if (detected != null) dayFirstEff = detected;
  }

  final headers = detectStatementHeaders(lines);
  final sections = <_Section>[];
  var confidentLayout = false;
  if (headers.isNotEmpty) {
    for (var k = 0; k < headers.length; k++) {
      final h = headers[k];
      final from = h.lineIndex + 1;
      final to = k + 1 < headers.length
          ? headers[k + 1].lineIndex
          : lines.length;
      _Layout layout;
      if (template != null) {
        final a = h.roles.where((r) => r != StatementColumnRole.ignore).toSet();
        final b = template.mapping.roles
            .where((r) => r != StatementColumnRole.ignore)
            .toSet();
        if (a.length != b.length || !a.containsAll(b)) continue;
        layout = (
          cuts: template.cutPoints,
          roles: template.mapping.roles,
          texts: const <String>[],
        );
      } else {
        layout = _layoutFromHeader(h, lines.sublist(from, to), dayFirstEff);
      }
      sections.add(_readSection(lines, from, to, layout, null, dayFirstEff));
    }
    confidentLayout = template == null;
  }
  if (sections.every((s) => s.dataRows == 0)) {
    sections.clear();
    confidentLayout = false;
    _Layout? layout;
    if (template != null) {
      layout = (
        cuts: template.cutPoints,
        roles: template.mapping.roles,
        texts: const <String>[],
      );
    } else {
      final cuts = _inferCuts([
        for (final l in lines)
          if (_looksLikeDataLine(l, dayFirstEff)) l,
      ]);
      if (cuts.isNotEmpty) {
        layout = (
          cuts: cuts,
          roles: List.filled(cuts.length + 1, StatementColumnRole.ignore),
          texts: const <String>[],
        );
      }
    }
    if (layout == null) return empty;
    // No header: the whole text is one table; the date column is found by
    // votes (or the template).
    final s = _readSection(
      lines,
      0,
      lines.length,
      layout,
      template?.mapping.indexOf(StatementColumnRole.date),
      dayFirstEff,
    );
    if (s.dataRows > 0) sections.add(s);
  }
  final candidates = [
    for (final s in sections)
      if (s.dataRows > 0) s,
  ];
  if (candidates.isEmpty) return empty;

  // Group sections with the same columns; pick the table.
  final groups = <String, List<_Section>>{};
  for (final s in candidates) {
    groups.putIfAbsent(s.signature, () => []).add(s);
  }
  int rowsOf(List<_Section> g) => g.fold(0, (a, s) => a + s.dataRows);
  final ordered = groups.values.toList()
    ..sort((a, b) => rowsOf(b).compareTo(rowsOf(a)));
  final mostRows = rowsOf(ordered.first);
  List<_Section> chosen = ordered.first;
  for (final g in ordered) {
    // A table with a Balance column wins unless it is much shorter.
    if (g.first.hasBalance && rowsOf(g) * 2 >= mostRows) {
      chosen = g;
      break;
    }
  }
  final kept = <_Section>[];
  for (final s in chosen) {
    if (kept.isNotEmpty && _repeats(s, kept)) continue;
    kept.add(s);
  }
  final layout = kept.first.layout;
  final columns = layout.cuts.length + 1;
  var rows = [for (final s in kept) ...s.rows];

  // Years and one date format.
  final roleDate = layout.roles.indexOf(StatementColumnRole.date);
  final dateCol = roleDate >= 0
      ? roleDate
      : _suggest(
          [
            for (final r in rows)
              if (!r.continuation) r.cells,
          ],
          columns,
          dayFirstEff,
        ).indexOf(StatementColumnRole.date);
  if (dateCol >= 0) {
    final parsed = <Object?>[];
    final idx = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].continuation) continue;
      final t = rows[i].cells[dateCol];
      parsed.add(
        parseStatementDate(t, dayFirst: dayFirstEff) ??
            parsePartialStatementDate(t, dayFirst: dayFirstEff),
      );
      idx.add(i);
    }
    final resolved = resolveStatementYears(
      parsed,
      anchor: _anchorDate(lines, dayFirstEff, today ?? DateTime.now()),
    );
    rows = [...rows];
    for (var k = 0; k < idx.length; k++) {
      final d = resolved[k];
      if (d == null) continue;
      final cells = [...rows[idx[k]].cells];
      cells[dateCol] =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      rows[idx[k]] = StatementRawRow(cells);
    }
  }

  final body = [
    for (final r in rows)
      if (!r.continuation) r.cells,
  ];
  var roles = layout.roles;
  var confident = false;
  if (template != null) {
    roles = template.mapping.roles;
    confident = true;
  } else if (confidentLayout) {
    // A header without a description column still reads: take the
    // suggestion's description column.
    if (!roles.contains(StatementColumnRole.description)) {
      final sug = _suggest(body, columns, true);
      final d = sug.indexOf(StatementColumnRole.description);
      if (d >= 0 && roles[d] == StatementColumnRole.ignore) {
        roles = [...roles]..[d] = StatementColumnRole.description;
      }
    }
    confident = StatementMapping(
      roles: roles,
      currency: Currency.of('EGP'),
    ).isValid;
  } else {
    roles = _suggest(body, columns, true);
  }
  final (opening, closing) = _scanBalances(lines, dayFirstEff);
  return StatementTable(
    cutPoints: layout.cuts,
    rows: rows,
    suggestedRoles: roles,
    confident: confident,
    headerTexts: layout.texts,
    openingBalance: opening,
    closingBalance: closing,
    suggestedCurrency: _detectCurrency(lines),
    dayFirst: dayFirstEff,
  );
}
