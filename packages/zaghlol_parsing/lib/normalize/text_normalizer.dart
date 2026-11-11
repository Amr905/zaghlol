/// Text normalization shared by parsing, voice, OCR and search (T-013).
///
/// Three levels, each idempotent and pure:
/// - [normalizeText]: display-safe (digits, separators, invisible marks).
/// - [foldForMatching]: also drops tatweel and harakat, for regex matching.
/// - [foldKey]: also folds letter variants and lowercases ASCII, for keys.
///
/// Folding is for matching and keys only. Stored bodies, display strings
/// and merchant display names must never go through the two fold levels.
library;

/// Display-safe normalization: Arabic-Indic and extended digits to ASCII,
/// `٫` to `.`, `٬` to `,`, odd spaces to a plain space, invisible direction
/// marks removed, whitespace runs collapsed and trimmed.
String normalizeText(String input) => _transform(input, _Level.display);

/// [normalizeText] plus removal of tatweel (U+0640) and harakat
/// (U+064B-0652, U+0670).
String foldForMatching(String input) => _transform(input, _Level.matching);

/// [foldForMatching] plus `أ إ آ ٱ` to `ا`, `ى` to `ي`, `ة` to `ه` and ASCII
/// lowercase.
String foldKey(String input) => _transform(input, _Level.key);

/// Folds only the Arabic letter variants (`أ إ آ ٱ` to `ا`, `ى` to `ي`,
/// `ة` to `ه`) and drops tatweel and harakat, leaving case, digits and
/// spacing alone. Used on template pattern literals (registry), where
/// lowercasing would corrupt escapes such as `\S` and `\D`.
String foldArabicVariants(String input) {
  final out = StringBuffer();
  // Code units, not runes: no mapped character is a surrogate half.
  for (final unit in input.codeUnits) {
    if (_isMatchingMark(unit)) {
      continue;
    }
    switch (unit) {
      case 0x0623:
      case 0x0625:
      case 0x0622:
      case 0x0671:
        out.writeCharCode(0x0627);
      case 0x0649:
        out.writeCharCode(0x064A);
      case 0x0629:
        out.writeCharCode(0x0647);
      default:
        out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// A [foldKey] result with a map back to the original text.
///
/// [origin] has one entry per code unit of [text]: the index of the original
/// code unit it came from (a collapsed run of spaces maps to its first
/// whitespace). A span `[start, end)` of [text] therefore covers the original
/// span `[origin[start], origin[end - 1] + 1)`.
final class FoldedText {
  const FoldedText(this.text, this.origin);

  final String text;
  final List<int> origin;

  /// The original substring under the folded span `[start, end)`, or null
  /// when the span is empty or out of range.
  String? originalSpan(String original, int start, int end) {
    if (start < 0 || end > text.length || start >= end) {
      return null;
    }
    final from = origin[start];
    final to = origin[end - 1] + 1;
    if (to > original.length || from >= to) {
      return null;
    }
    return original.substring(from, to);
  }
}

/// [foldKey] that also records where each folded code unit came from. The
/// `text` is identical to `foldKey(input)` (tested), so regexes compiled for
/// folded text run unchanged and their captures can be mapped back.
FoldedText foldKeyIndexed(String input) {
  final out = StringBuffer();
  final origin = <int>[];
  var pendingSpaceAt = -1;
  var wroteAny = false;
  final units = input.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (_isSpace(unit)) {
      if (pendingSpaceAt < 0) {
        pendingSpaceAt = i;
      }
      continue;
    }
    if (_isInvisible(unit) || _isMatchingMark(unit)) {
      continue;
    }
    if (pendingSpaceAt >= 0 && wroteAny) {
      out.writeCharCode(_space);
      origin.add(pendingSpaceAt);
    }
    pendingSpaceAt = -1;
    wroteAny = true;
    out.writeCharCode(_foldLetter(_mapChar(unit)));
    origin.add(i);
  }
  return FoldedText(out.toString(), origin);
}

enum _Level { display, matching, key }

const int _space = 0x20;

String _transform(String input, _Level level) {
  final out = StringBuffer();
  var pendingSpace = false;
  var wroteAny = false;

  void emit(int unit) {
    if (pendingSpace && wroteAny) {
      out.writeCharCode(_space);
    }
    pendingSpace = false;
    wroteAny = true;
    out.writeCharCode(unit);
  }

  for (final unit in input.codeUnits) {
    if (_isSpace(unit)) {
      pendingSpace = true;
      continue;
    }
    if (_isInvisible(unit)) {
      continue;
    }
    if (level != _Level.display && _isMatchingMark(unit)) {
      continue;
    }
    var mapped = _mapChar(unit);
    if (level == _Level.key) {
      mapped = _foldLetter(mapped);
    }
    emit(mapped);
  }
  return out.toString();
}

bool _isSpace(int u) {
  return u == _space ||
      (u >= 0x09 && u <= 0x0D) ||
      u == 0x85 || // NEL: a line terminator for ICU `.` (T-035 §3)
      u == 0xA0 ||
      u == 0x202F ||
      u == 0x2009 ||
      u == 0x2028 ||
      u == 0x2029;
}

bool _isInvisible(int u) {
  return (u >= 0x200B && u <= 0x200F) ||
      (u >= 0x202A && u <= 0x202E) ||
      (u >= 0x2066 && u <= 0x2069) ||
      u == 0x061C ||
      u == 0x2060 || // word joiner
      u == 0x00AD || // soft hyphen
      u == 0xFEFF;
}

bool _isMatchingMark(int u) {
  return u == 0x0640 || (u >= 0x064B && u <= 0x0652) || u == 0x0670;
}

int _mapChar(int u) {
  if (u >= 0x0660 && u <= 0x0669) {
    return 0x30 + (u - 0x0660);
  }
  if (u >= 0x06F0 && u <= 0x06F9) {
    return 0x30 + (u - 0x06F0);
  }
  if (u == 0x066B) {
    return 0x2E;
  }
  if (u == 0x066C) {
    return 0x2C;
  }
  return u;
}

int _foldLetter(int u) {
  switch (u) {
    case 0x0623: // alef with hamza above
    case 0x0625: // alef with hamza below
    case 0x0622: // alef with madda
    case 0x0671: // alef wasla
      return 0x0627;
    case 0x0649: // alef maksura
      return 0x064A;
    case 0x0629: // teh marbuta
      return 0x0647;
  }
  if (u >= 0x41 && u <= 0x5A) {
    return u + 0x20;
  }
  return u;
}
