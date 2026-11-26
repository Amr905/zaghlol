/// Matching fold and span replacement shared by the scrub and the masker
/// (T-278). Internal: not exported.
library;

import '../../normalize/text_normalizer.dart';

/// [foldKeyIndexed] plus: apostrophes, backticks and dots dropped, `-`, `_`
/// and `/` read as a space (so `Banque-Misr`, `C.I.B` and `Domino's` match
/// their plain forms). The text keeps an origin table into [input].
FoldedText looseFold(String input) {
  final f = foldKeyIndexed(input);
  final t = f.text;
  final out = StringBuffer();
  final origin = <int>[];
  var pendingSpace = -1;
  var wrote = false;
  for (var i = 0; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c == 0x27 || c == 0x2019 || c == 0x2018 || c == 0x60 || c == 0x2E) {
      continue;
    }
    if (c == 0x20 || c == 0x2D || c == 0x5F || c == 0x2F) {
      if (pendingSpace < 0) {
        pendingSpace = f.origin[i];
      }
      continue;
    }
    if (pendingSpace >= 0 && wrote) {
      out.writeCharCode(0x20);
      origin.add(pendingSpace);
    }
    pendingSpace = -1;
    wrote = true;
    out.writeCharCode(c);
    origin.add(f.origin[i]);
  }
  return FoldedText(out.toString(), origin);
}

/// Folded key of one alias / name (same pipeline as [looseFold]).
String looseKey(String input) => looseFold(input).text;

/// A replacement of the folded span `[start, end)`.
final class SpanReplacement {
  const SpanReplacement(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

bool _isTrailingMark(int u) =>
    u == 0x0640 || (u >= 0x064B && u <= 0x0652) || u == 0x0670;

/// Applies [reps] (sorted by start, not overlapping) to [original] through
/// the origin table of [folded]. Text outside the spans is untouched.
String applyReplacements(
  String original,
  FoldedText folded,
  List<SpanReplacement> reps,
) {
  final out = StringBuffer();
  var cursor = 0;
  for (final r in reps) {
    if (r.start < 0 || r.end > folded.text.length || r.start >= r.end) {
      continue;
    }
    var from = folded.origin[r.start];
    var to = folded.origin[r.end - 1] + 1;
    while (to < original.length && _isTrailingMark(original.codeUnitAt(to))) {
      to++;
    }
    if (from < cursor) {
      from = cursor;
    }
    if (from >= to) {
      continue;
    }
    out.write(original.substring(cursor, from));
    out.write(r.text);
    cursor = to;
  }
  out.write(original.substring(cursor));
  return out.toString();
}
