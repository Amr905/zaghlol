import '../normalize/text_normalizer.dart';
import 'registry_models.dart';

/// Longest accepted pattern source.
const int maxPatternLength = 600;

/// Most unbounded wildcards (`.*`, `.+`, `.*?`) one pattern may use.
const int maxUnboundedWildcards = 6;

/// Largest repeat count of a group that holds an unbounded quantifier before
/// the pattern is flagged (`(\d+,){1,3}` is fine, `(a+){1,50}` is not).
const int maxBoundedRepeat = 3;

/// Compiles a registry pattern, or returns null when it is not valid.
///
/// Dart's `RegExp` has no inline flags, so a single leading `(?i)` is
/// accepted and dropped (every pattern is case-insensitive anyway, because
/// message text is lowercased by `foldKey`). Arabic letter variants in the
/// pattern are folded the same way as the body (alef, ya, ta marbuta, tatweel
/// and harakat) so `بطاقة` and `بطاقه` match each other.
CompiledPattern? compilePattern(String source) {
  if (source.isEmpty || source.length > maxPatternLength) {
    return null;
  }
  var body = source;
  if (body.startsWith('(?i)')) {
    body = body.substring(4);
  }
  try {
    final regex = RegExp(foldArabicVariants(body), caseSensitive: false);
    return CompiledPattern(source, regex);
  } on FormatException {
    return null;
  }
}

/// A short list of reasons a pattern is rejected as a possible catastrophic
/// backtracker; empty means "not flagged".
///
/// This is a **heuristic over the pattern text**, not a proof: Dart has no
/// regex timeout, so the registry refuses the shapes that cause exponential
/// or high-polynomial blowup and relies on that plus the length cap and the
/// per-message budget tests. It flags:
/// - `nested_quantifier`: an unbounded quantifier on a group that itself
///   contains an unbounded quantifier (`(a+)+`, `(.*x)*`);
/// - `nested_bounded_quantifier`: the same with a bounded repeat above
///   [maxBoundedRepeat] (`(a+){1,50}`);
/// - `ambiguous_alternation`: a repeating group with an empty or duplicate
///   alternative, an alternative that is also written optional, or one
///   alternative that is a prefix of another (`(a|a)*`, `(a|)+`, `(a|a?)+`,
///   `(a|aa)+`);
/// - `lookaround` and `backreference`: not needed by templates and hard to
///   bound;
/// - `too_many_wildcards`: more than [maxUnboundedWildcards] unbounded `.`;
/// - `too_long`.
///
/// Overlap that is not a literal prefix (`(\w|\d)+`) is not detected, and
/// the runtime guard of the fixture runner only measures, it can not stop a
/// running match.
List<String> backtrackingProblems(String source) {
  final problems = <String>{};
  if (source.length > maxPatternLength) {
    problems.add('too_long');
    return problems.toList();
  }
  final stack = <_Group>[_Group(isRoot: true)];
  var wildcards = 0;
  final n = source.length;
  var i = 0;
  while (i < n) {
    final c = source[i];
    final start = i;
    var atomIsWildcard = false;
    var isAtom = true;
    _Group? closed;
    if (c == r'\') {
      if (i + 1 < n) {
        final next = source[i + 1];
        if (RegExp('[1-9]').hasMatch(next) || next == 'k') {
          problems.add('backreference');
        }
      }
      i += 2;
    } else if (c == '[') {
      i = _skipClass(source, i);
    } else if (c == '(') {
      final g = _Group(openAt: i);
      i += 1;
      if (i < n && source[i] == '?') {
        // Group prefix: `?:`, `?<name>`, `?=`, `?!`, `?<=`, `?<!`.
        final next = i + 1 < n ? source[i + 1] : '';
        final after = i + 2 < n ? source[i + 2] : '';
        if (next == '=' ||
            next == '!' ||
            (next == '<' && (after == '=' || after == '!'))) {
          problems.add('lookaround');
        }
        if (next == '<' && after != '=' && after != '!') {
          final close = source.indexOf('>', i);
          i = close < 0 ? n : close + 1;
        } else {
          i += next == '<' ? 3 : 2;
        }
      }
      stack.add(g);
      // A quantifier cannot follow an opening parenthesis.
      continue;
    } else if (c == ')') {
      if (stack.length > 1) {
        closed = stack.removeLast();
      }
      isAtom = closed != null;
      i += 1;
    } else if (c == '|') {
      stack.last.endAlternative();
      isAtom = false;
      i += 1;
    } else {
      atomIsWildcard = c == '.';
      i += 1;
    }
    // A quantifier directly after an atom or a closed group.
    final q = _readQuantifier(source, i);
    if (q != null) {
      i = q.end;
      if (closed != null) {
        closed.finish();
        if (q.unbounded && closed.hasUnbounded) {
          problems.add('nested_quantifier');
        } else if (q.repeats &&
            (q.max ?? 0) > maxBoundedRepeat &&
            closed.hasUnbounded) {
          problems.add('nested_bounded_quantifier');
        }
        if (q.repeats && closed.ambiguousAlternatives) {
          problems.add('ambiguous_alternation');
        }
        stack.last.hasUnbounded =
            stack.last.hasUnbounded || closed.hasUnbounded || q.unbounded;
      } else if (q.unbounded) {
        stack.last.hasUnbounded = true;
        if (atomIsWildcard) {
          wildcards += 1;
        }
      }
    } else if (closed != null) {
      closed.finish();
      stack.last.hasUnbounded = stack.last.hasUnbounded || closed.hasUnbounded;
    }
    if (isAtom) {
      // The atom's own source text (a closed group's whole text), so
      // alternatives compare by what they are written as.
      stack.last.addAtom(
        source.substring(closed?.openAt ?? start, i > n ? n : i),
      );
    }
  }
  if (wildcards > maxUnboundedWildcards) {
    problems.add('too_many_wildcards');
  }
  return problems.toList()..sort();
}

int _skipClass(String s, int start) {
  var i = start + 1;
  if (i < s.length && s[i] == '^') {
    i += 1;
  }
  // A `]` first in the class is a literal.
  if (i < s.length && s[i] == ']') {
    i += 1;
  }
  while (i < s.length && s[i] != ']') {
    i += s[i] == r'\' ? 2 : 1;
  }
  return i + 1;
}

final class _Quantifier {
  const _Quantifier(
    this.end, {
    required this.unbounded,
    required this.repeats,
    required this.max,
  });

  final int end;

  /// Largest repeat count, null when unbounded.
  final int? max;
  final bool unbounded;

  /// More than one repetition is possible.
  final bool repeats;
}

_Quantifier? _readQuantifier(String s, int at) {
  if (at >= s.length) {
    return null;
  }
  final c = s[at];
  var end = at + 1;
  var unbounded = false;
  var repeats = true;
  int? max;
  if (c == '*' || c == '+') {
    unbounded = true;
  } else if (c == '?') {
    repeats = false;
    max = 1;
  } else if (c == '{') {
    final m = RegExp(r'^\{(\d+)(,(\d*))?\}').firstMatch(s.substring(at));
    if (m == null) {
      return null;
    }
    end = at + m.end;
    final hasComma = m.group(2) != null;
    final upper = m.group(3) ?? '';
    unbounded = hasComma && upper.isEmpty;
    max = unbounded
        ? null
        : (hasComma ? int.tryParse(upper) : int.tryParse(m.group(1)!));
    repeats = unbounded || (max ?? 2) > 1;
  } else {
    return null;
  }
  if (end < s.length && (s[end] == '?' || s[end] == '+')) {
    end += 1; // lazy or possessive suffix
  }
  return _Quantifier(end, unbounded: unbounded, repeats: repeats, max: max);
}

/// Bookkeeping for one open group.
final class _Group {
  _Group({this.isRoot = false, this.openAt = 0});

  final bool isRoot;
  final int openAt;
  bool hasUnbounded = false;
  final List<StringBuffer> _alternatives = [StringBuffer()];
  bool ambiguousAlternatives = false;

  void addAtom(String c) => _alternatives.last.write(c);

  void endAlternative() => _alternatives.add(StringBuffer());

  void finish() {
    if (_alternatives.length < 2) {
      return;
    }
    final texts = [for (final a in _alternatives) a.toString()];
    final seen = <String>{};
    for (final text in texts) {
      if (text.isEmpty || !seen.add(text)) {
        ambiguousAlternatives = true;
      }
    }
    for (final a in texts) {
      // `x` next to `x?`.
      if (a.length > 1 &&
          a.endsWith('?') &&
          !a.endsWith(r'\?') &&
          seen.contains(a.substring(0, a.length - 1))) {
        ambiguousAlternatives = true;
      }
      // One alternative is the start of another (`a|aa`).
      for (final b in texts) {
        if (a.isNotEmpty && b.length > a.length && b.startsWith(a)) {
          ambiguousAlternatives = true;
        }
      }
    }
  }
}
