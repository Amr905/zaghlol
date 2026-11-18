// T-156b: recognised OCR lines to positioned fragments, so a scanned
// statement goes through the same table detector as a text PDF. Pure Dart.
//
// An OCR engine returns one box per line, often a whole table row. A row is
// split into a date, a description and one cell per trailing amount, with
// x positions spread over the line's box by character offset (digits are
// the same width in almost every font, so amounts land where they were
// printed; the right-most amount ends exactly at the box edge). Header and
// other lines stay whole. Recognised text is sensitive: no `toString` here
// prints it.

import 'pdf_text_types.dart';
import 'statement_dates.dart';

/// One recognised line: [x], [y], [width], [height] are 0..1, origin top-left.
final class OcrLineBox {
  const OcrLineBox({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  @override
  String toString() => 'OcrLineBox';
}

/// Most lines taken from one page of OCR output.
const int maxOcrLinesPerPage = 2000;

final RegExp _noise = RegExp(r'^[\s|_\-–—=~.,:;·•*]*$');
final RegExp _amountToken = RegExp(
  r'^[\-(−]?[$£€]?\d[\d,]*[.,]\d{1,3}\)?-?$|^[\-(−]?[$£€]?[.,]\d{1,3}\)?$',
);
final RegExp _symbolOnly = RegExp(r'^[$£€]$');

bool _isDate(String t) =>
    parseStatementDate(t) != null ||
    parseStatementDate(t, dayFirst: false) != null ||
    parsePartialStatementDate(t) != null ||
    parsePartialStatementDate(t, dayFirst: false) != null;

/// Converts the lines of one page. [pageHeightPoints] turns the 0..1 vertical
/// position into the whole points the table detector works in.
List<PdfTextFragment> ocrLinesToFragments(
  List<OcrLineBox> lines, {
  required int page,
  required int pageHeightPoints,
}) {
  final out = <PdfTextFragment>[];
  final take = lines.length > maxOcrLinesPerPage
      ? lines.sublist(0, maxOcrLinesPerPage)
      : lines;
  for (final l in take) {
    final text = l.text.trim();
    if (text.isEmpty || _noise.hasMatch(text)) continue;
    final x0 = (l.x * 1000).round().clamp(0, 1000);
    final x1 = ((l.x + l.width) * 1000).round().clamp(x0, 1000);
    final y = ((l.y + l.height / 2) * pageHeightPoints).round();
    PdfTextFragment frag(String t, int a, int b, {bool brk = false}) =>
        PdfTextFragment(
          page: page,
          text: t,
          x0: a,
          x1: b,
          y: y,
          breakBefore: brk,
        );

    // Tokens with their character offsets.
    final tokens = <(String, int, int)>[];
    for (final m in RegExp(r'\S+').allMatches(text)) {
      tokens.add((m.group(0)!, m.start, m.end));
    }
    // Join a lone currency symbol with the amount after it.
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (_symbolOnly.hasMatch(tokens[i].$1)) {
        tokens[i] = (
          '${tokens[i].$1}${tokens[i + 1].$1}',
          tokens[i].$2,
          tokens[i + 1].$3,
        );
        tokens.removeAt(i + 1);
      }
    }
    final hasDate = tokens.isNotEmpty && _isDate(tokens.first.$1);
    final bodyStart = hasDate ? 1 : 0;
    var tail = tokens.length;
    while (tail > bodyStart && _amountToken.hasMatch(tokens[tail - 1].$1)) {
      tail--;
    }
    final amounts = tokens.length - tail;
    if (tokens.length < 2 || (!hasDate && amounts == 0)) {
      out.add(frag(tokens.length == 1 ? tokens.single.$1 : text, x0, x1));
      continue;
    }
    final width = x1 - x0;
    int at(int offset) => x0 + (width * offset / text.length).round();
    var first = true;
    void seg(List<(String, int, int)> toks) {
      if (toks.isEmpty) return;
      out.add(
        frag(
          toks.map((t) => t.$1).join(' '),
          at(toks.first.$2),
          at(toks.last.$3),
          brk: !first,
        ),
      );
      first = false;
    }

    if (hasDate) seg([tokens.first]);
    seg(tokens.sublist(bodyStart, tail));
    for (var i = tail; i < tokens.length; i++) {
      seg([tokens[i]]);
    }
  }
  return out;
}
