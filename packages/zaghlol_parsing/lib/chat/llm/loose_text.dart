/// Matching fold and span replacement shared by the scrub and the masker
/// (T-328). Internal: not exported.
library;

import '../../normalize/text_normalizer.dart';

/// Matching fold for the scrub and the masker (T-328, FR-LLM-18, D-92). It is
/// deliberately wider than the parser's `foldKey` (which is not touched):
/// - Arabic digits (U+0660-9, U+06F0-9) and fullwidth forms (U+FF01-FF5E)
///   become ASCII; ASCII is lowercased;
/// - Persian/Urdu letters read as their Arabic twins (ک ی ە ھ ہ ۃ ...),
///   alef/waw/yeh with hamza or madda read as the bare letter (precomposed
///   or with a combining U+0653-0655), ة as ه, ى as ي;
/// - Arabic presentation forms (U+FB50-FDFF, U+FE70-FEFE) read as their
///   base letters (lam-alef ligatures as two letters);
/// - Latin accents fold to the base letter (NFD marks U+0300-036F dropped);
/// - tatweel, harakat, zero-width, bidi and other invisible characters drop;
/// - apostrophes, backticks and dots are dropped; `-`, `_` and `/` read as a
///   space (so `Banque-Misr`, `C.I.B` and `Domino's` match their plain forms).
/// The text keeps an origin table into [input].
FoldedText looseFold(String input) => _fold(input, loose: true);

/// The same character mapping but with dots, hyphens and slashes kept, for
/// the scrub's regexes (phones, addresses, digit runs).
FoldedText scrubFold(String input) => _fold(input, loose: false);

FoldedText _fold(String input, {required bool loose}) {
  final out = StringBuffer();
  final origin = <int>[];
  var pendingSpace = -1;
  var wrote = false;
  final units = input.codeUnits;

  void emit(String s, int at) {
    for (var k = 0; k < s.length; k++) {
      out.writeCharCode(s.codeUnitAt(k));
      origin.add(at);
    }
  }

  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (_isSpace(u) ||
        (loose &&
            (u == 0x2D ||
                u == 0x5F ||
                u == 0x2F ||
                u == 0x2212 ||
                (u >= 0x2010 && u <= 0x2015)))) {
      if (pendingSpace < 0) {
        pendingSpace = i;
      }
      continue;
    }
    if (_isIgnorable(u)) {
      continue;
    }
    final mapped = _mapUnit(u);
    if (loose && mapped == '.') {
      continue;
    }
    if (loose &&
        (mapped == "'" ||
            mapped == '`' ||
            u == 0x2019 ||
            u == 0x2018 ||
            u == 0xB4)) {
      continue;
    }
    if (mapped.isEmpty) {
      continue;
    }
    if (pendingSpace >= 0 && wrote) {
      emit(' ', pendingSpace);
    }
    pendingSpace = -1;
    wrote = true;
    emit(mapped, i);
  }
  return FoldedText(out.toString(), origin);
}

bool _isSpace(int u) =>
    u == 0x20 ||
    (u >= 0x09 && u <= 0x0D) ||
    u == 0x85 ||
    u == 0xA0 ||
    u == 0x1680 ||
    (u >= 0x2000 && u <= 0x200A) ||
    u == 0x2028 ||
    u == 0x2029 ||
    u == 0x202F ||
    u == 0x205F ||
    u == 0x3000;

/// Zero-width, bidi, joiners, soft hyphen, BOM, variation selectors, tatweel,
/// Arabic marks (harakat, hamza above/below, madda, Quranic), combining
/// diacritics.
bool _isIgnorable(int u) =>
    (u >= 0x200B && u <= 0x200F) ||
    (u >= 0x202A && u <= 0x202E) ||
    (u >= 0x2060 && u <= 0x206F) ||
    u == 0x061C ||
    u == 0x00AD ||
    u == 0x034F ||
    u == 0x180E ||
    u == 0xFEFF ||
    (u >= 0xFE00 && u <= 0xFE0F) ||
    u == 0x0640 ||
    (u >= 0x0610 && u <= 0x061A) ||
    (u >= 0x064B && u <= 0x065F) ||
    u == 0x0670 ||
    (u >= 0x06D6 && u <= 0x06DC) ||
    (u >= 0x06DF && u <= 0x06E4) ||
    (u >= 0x06E7 && u <= 0x06E8) ||
    (u >= 0x06EA && u <= 0x06ED) ||
    (u >= 0x0300 && u <= 0x036F);

String _one(int u) => String.fromCharCode(u);

String _mapUnit(int u) {
  if (u < 0x80) {
    return (u >= 0x41 && u <= 0x5A) ? _one(u + 0x20) : _one(u);
  }
  if (u >= 0x0660 && u <= 0x0669) {
    return _one(0x30 + u - 0x0660);
  }
  if (u >= 0x06F0 && u <= 0x06F9) {
    return _one(0x30 + u - 0x06F0);
  }
  if (u >= 0xFF10 && u <= 0xFF19) {
    return _one(0x30 + u - 0xFF10);
  }
  if (u >= 0xFF21 && u <= 0xFF3A) {
    return _one(u - 0xFF21 + 0x61);
  }
  if (u >= 0xFF01 && u <= 0xFF5E) {
    return _one(u - 0xFEE0);
  }
  switch (u) {
    case 0x066B:
      return '.';
    case 0x066C:
      return ',';
    case 0x060C:
      return ',';
  }
  if (u >= 0xC0 && u <= 0x17F) {
    return _latin(u);
  }
  if (u >= 0xFB00 && u <= 0xFB06) {
    return const ['ff', 'fi', 'fl', 'ffi', 'ffl', 'st', 'st'][u - 0xFB00];
  }
  if (u >= 0x0600 && u <= 0x06FF) {
    return _arabicLetter(u);
  }
  if (u >= 0x0750 && u <= 0x077F) {
    return _one(u);
  }
  if ((u >= 0xFB50 && u <= 0xFDFF) || (u >= 0xFE70 && u <= 0xFEFE)) {
    final base = _presentation[u];
    if (base != null) {
      final b = StringBuffer();
      for (final r in base.codeUnits) {
        b.write(_arabicLetter(r));
      }
      return b.toString();
    }
  }
  return _one(u);
}

String _arabicLetter(int u) {
  switch (u) {
    case 0x0622: // آ
    case 0x0623: // أ
    case 0x0625: // إ
    case 0x0671: // ٱ
    case 0x0672:
    case 0x0673:
    case 0x0675:
      return 'ا';
    case 0x0624: // ؤ
    case 0x0676:
    case 0x0677:
    case 0x06C4:
    case 0x06C5:
    case 0x06C6:
    case 0x06C7:
    case 0x06C8:
    case 0x06C9:
    case 0x06CA:
    case 0x06CB:
      return 'و';
    case 0x0626: // ئ
    case 0x0649: // ى
    case 0x06CC: // ی
    case 0x06CD:
    case 0x06CE:
    case 0x06D0:
    case 0x06D1:
    case 0x06D2:
    case 0x06D3:
    case 0x0678:
      return 'ي';
    case 0x0629: // ة
    case 0x06BE: // ھ
    case 0x06C1: // ہ
    case 0x06C2:
    case 0x06C3:
    case 0x06D5: // ە
    case 0x06C0:
      return 'ه';
    case 0x06A9: // ک
    case 0x06AA:
    case 0x06AB:
    case 0x06AC:
    case 0x06AD:
    case 0x06AE:
    case 0x06AF: // گ
    case 0x06B0:
    case 0x06B1:
    case 0x06B2:
    case 0x06B3:
    case 0x06B4:
      return 'ك';
    case 0x06A4: // ڤ
    case 0x06A5:
    case 0x06A6:
    case 0x06A7:
    case 0x06A8:
      return 'ف';
    case 0x067E: // پ
    case 0x067B:
    case 0x067A:
      return 'ب';
    case 0x0686: // چ
      return 'ج';
    case 0x0698: // ژ
      return 'ز';
    case 0x06BA:
    case 0x06BB:
      return 'ن';
    case 0x0679:
    case 0x067C:
    case 0x067D:
      return 'ت';
    case 0x0688:
    case 0x068A:
      return 'د';
    case 0x0691:
      return 'ر';
  }
  return _one(u);
}

const _latinLower = [
  'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', //
  'i', 'i', 'd', 'n', 'o', 'o', 'o', 'o', 'o', '×', 'o', 'u', 'u', 'u',
  'u', 'y', 'þ', 'y',
];

String _latin(int u) {
  if (u <= 0xFF) {
    if (u == 0xDF) {
      return 'ss';
    }
    if (u == 0xD7 || u == 0xF7) {
      return _one(u);
    }
    if (u == 0xDE) {
      return _one(0xFE);
    }
    return _latinLower[(u - 0xC0) % 32];
  }
  if (u >= 0x100 && u <= 0x105) return 'a';
  if (u >= 0x106 && u <= 0x10D) return 'c';
  if (u >= 0x10E && u <= 0x111) return 'd';
  if (u >= 0x112 && u <= 0x11B) return 'e';
  if (u >= 0x11C && u <= 0x123) return 'g';
  if (u >= 0x124 && u <= 0x127) return 'h';
  if (u >= 0x128 && u <= 0x131) return 'i';
  if (u == 0x132 || u == 0x133) return 'ij';
  if (u == 0x134 || u == 0x135) return 'j';
  if (u >= 0x136 && u <= 0x138) return 'k';
  if (u >= 0x139 && u <= 0x142) return 'l';
  if (u >= 0x143 && u <= 0x14B) return 'n';
  if (u >= 0x14C && u <= 0x151) return 'o';
  if (u == 0x152 || u == 0x153) return 'oe';
  if (u >= 0x154 && u <= 0x159) return 'r';
  if (u >= 0x15A && u <= 0x161) return 's';
  if (u >= 0x162 && u <= 0x167) return 't';
  if (u >= 0x168 && u <= 0x173) return 'u';
  if (u == 0x174 || u == 0x175) return 'w';
  if (u >= 0x176 && u <= 0x178) return 'y';
  if (u >= 0x179 && u <= 0x17E) return 'z';
  if (u == 0x17F) return 's';
  return _one(u);
}

/// Arabic presentation forms to base letters (as plain Arabic text; the
/// result is folded again by [_arabicLetter]).
final Map<int, String> _presentation = () {
  final m = <int, String>{};
  void forms(int from, int n, String base) {
    for (var k = 0; k < n; k++) {
      m[from + k] = base;
    }
  }

  forms(0xFE80, 1, 'ء');
  forms(0xFE81, 2, 'آ');
  forms(0xFE83, 2, 'أ');
  forms(0xFE85, 2, 'ؤ');
  forms(0xFE87, 2, 'إ');
  forms(0xFE89, 4, 'ئ');
  forms(0xFE8D, 2, 'ا');
  forms(0xFE8F, 4, 'ب');
  forms(0xFE93, 2, 'ة');
  forms(0xFE95, 4, 'ت');
  forms(0xFE99, 4, 'ث');
  forms(0xFE9D, 4, 'ج');
  forms(0xFEA1, 4, 'ح');
  forms(0xFEA5, 4, 'خ');
  forms(0xFEA9, 2, 'د');
  forms(0xFEAB, 2, 'ذ');
  forms(0xFEAD, 2, 'ر');
  forms(0xFEAF, 2, 'ز');
  forms(0xFEB1, 4, 'س');
  forms(0xFEB5, 4, 'ش');
  forms(0xFEB9, 4, 'ص');
  forms(0xFEBD, 4, 'ض');
  forms(0xFEC1, 4, 'ط');
  forms(0xFEC5, 4, 'ظ');
  forms(0xFEC9, 4, 'ع');
  forms(0xFECD, 4, 'غ');
  forms(0xFED1, 4, 'ف');
  forms(0xFED5, 4, 'ق');
  forms(0xFED9, 4, 'ك');
  forms(0xFEDD, 4, 'ل');
  forms(0xFEE1, 4, 'م');
  forms(0xFEE5, 4, 'ن');
  forms(0xFEE9, 4, 'ه');
  forms(0xFEED, 2, 'و');
  forms(0xFEEF, 2, 'ى');
  forms(0xFEF1, 4, 'ي');
  forms(0xFEF5, 2, 'لآ');
  forms(0xFEF7, 2, 'لأ');
  forms(0xFEF9, 2, 'لإ');
  forms(0xFEFB, 2, 'لا');
  // Presentation Forms-A: the common Persian/Urdu letters.
  forms(0xFB56, 4, 'ب'); // پ
  forms(0xFB7A, 4, 'ج'); // چ
  forms(0xFB8E, 2, 'ك');
  forms(0xFB90, 4, 'ك');
  forms(0xFBA6, 4, 'ه');
  forms(0xFBAA, 4, 'ه');
  forms(0xFBD3, 4, 'ك');
  forms(0xFBFC, 4, 'ي');
  forms(0xFB50, 2, 'ا');
  forms(0xFB6A, 4, 'ف');
  forms(0xFDF2, 1, 'الله');
  return m;
}();

/// Folded key of one alias / name (same pipeline as [looseFold]).
String looseKey(String input) => looseFold(input).text;

/// A replacement of the folded span `[start, end)`.
final class SpanReplacement {
  const SpanReplacement(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

bool _isTrailingMark(int u) => _isIgnorable(u);

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
