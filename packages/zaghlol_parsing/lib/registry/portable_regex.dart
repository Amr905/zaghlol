/// The portable regex subset of every Guard-bound pattern (T-035 design
/// note §3): sender regexes, drop patterns, last-4 patterns and the generic
/// hints.
///
/// The same text runs in three engines: Dart (ECMAScript, `unicode: true`),
/// Kotlin/Android (`java.util.regex`, ICU-backed) and Swift
/// (`NSRegularExpression`, ICU). They disagree on `\b \w \d \s`, case folding,
/// inline flags and nested character classes, so the subset below keeps only
/// constructs whose meaning is the same in all three on `foldKey` text.
library;

import '../normalize/text_normalizer.dart';

/// The text a registry pattern is exported as, and the text every Guard
/// (Dart, Kotlin, Swift) compiles: a single leading `(?i)` removed (the body
/// is ASCII-lowercased by `foldKey`, so patterns are written lowercase and
/// compiled case-sensitive) and the Arabic letter variants folded like the
/// body.
String guardPatternText(String source) {
  var body = source;
  if (body.startsWith('(?i)')) {
    body = body.substring(4);
  }
  return foldArabicVariants(body);
}

/// Compiles exported Guard pattern text exactly as the Dart Guard does.
/// Throws [FormatException] on invalid syntax.
RegExp compileGuardPattern(String exported) => RegExp(exported, unicode: true);

/// Characters that may be escaped anywhere (ECMAScript `SyntaxCharacter`
/// plus `/`): their escape means the literal character in every engine.
const String _metaEscapes = r'^$\.*+?()[]{}|/';

/// The one letter escape allowed: `\n`, a line feed in every engine. It is
/// meaningful only in the global drop patterns, which run on `foldKeyLines`
/// text (platform-channels §1.2); elsewhere it never matches.
const String _lineFeedEscape = 'n';

/// Shorthand classes and escapes whose meaning differs between the engines
/// (`\b \w \d \s` are Unicode-aware in ICU, ASCII in ECMAScript; `\p`, `\u`,
/// `\x` have different syntax).
const String _shorthand = 'bBwWdDsSpPux';

/// Problems that make [exported] (the output of [guardPatternText]) not
/// portable; empty means portable. Codes, sorted and unique:
/// `uppercase`, `shorthand_escape`, `backreference`, `escape`,
/// `control_char` (a raw control character; write a line feed as `\n`),
/// `inline_flag`, `lookaround`, `named_group`, `atomic_group`, `possessive`,
/// `posix_class`, `nested_class`, `class_set_operation`, `capture_groups`
/// (only when [maxCaptureGroups] is given and exceeded), `no_capture_group`
/// (only when [requireCaptureGroup]).
List<String> portableRegexProblems(
  String exported, {
  int? maxCaptureGroups,
  bool requireCaptureGroup = false,
}) {
  final problems = <String>{};
  final n = exported.length;
  var captures = 0;
  var i = 0;
  var inClass = false;
  var classStart = -1;
  while (i < n) {
    final c = exported.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      problems.add('uppercase');
    }
    if (c < 0x20 || c == 0x7F) {
      problems.add('control_char');
    }
    if (c == 0x5C) {
      // Backslash.
      if (i + 1 >= n) {
        problems.add('escape');
        break;
      }
      final next = exported[i + 1];
      if (_shorthand.contains(next)) {
        problems.add('shorthand_escape');
      } else if ((next.codeUnitAt(0) >= 0x30 && next.codeUnitAt(0) <= 0x39) ||
          next == 'k') {
        problems.add('backreference');
      } else if (!(_metaEscapes.contains(next) ||
          next == _lineFeedEscape ||
          (inClass && next == '-'))) {
        problems.add('escape');
      }
      if (next.codeUnitAt(0) >= 0x41 && next.codeUnitAt(0) <= 0x5A) {
        problems.add('uppercase');
      }
      i += 2;
      continue;
    }
    if (inClass) {
      if (c == 0x5B) {
        // `[` inside a class: ICU opens a nested set, ECMAScript a literal.
        if (i + 1 < n && exported[i + 1] == ':') {
          problems.add('posix_class');
        } else {
          problems.add('nested_class');
        }
      } else if ((c == 0x26 || c == 0x2D) &&
          i + 1 < n &&
          exported.codeUnitAt(i + 1) == c) {
        // `&&` and `--` are set operations in ICU.
        problems.add('class_set_operation');
      } else if (c == 0x5D && i > classStart + 1) {
        inClass = false;
      } else if (c == 0x5D && i == classStart + 1) {
        // `[]...`: ICU and ECMAScript disagree on a leading `]`.
        problems.add('nested_class');
        inClass = false;
      }
      i += 1;
      continue;
    }
    if (c == 0x5B) {
      inClass = true;
      classStart = i;
      if (i + 1 < n && exported[i + 1] == '^') {
        classStart = i + 1;
        i += 1;
      }
      i += 1;
      continue;
    }
    if (c == 0x28) {
      // `(`
      if (i + 1 < n && exported[i + 1] == '?') {
        final a = i + 2 < n ? exported[i + 2] : '';
        final b = i + 3 < n ? exported[i + 3] : '';
        if (a == ':') {
          // Non-capturing group: portable.
        } else if (a == '=' ||
            a == '!' ||
            (a == '<' && (b == '=' || b == '!'))) {
          problems.add('lookaround');
        } else if (a == '<' || a == 'P' || a == "'") {
          problems.add('named_group');
        } else if (a == '>') {
          problems.add('atomic_group');
        } else {
          problems.add('inline_flag');
        }
      } else {
        captures += 1;
      }
      i += 1;
      continue;
    }
    if (c == 0x2A || c == 0x2B || c == 0x3F || c == 0x7D) {
      // `* + ? }` followed by `+` is possessive in ICU.
      if (i + 1 < n && exported[i + 1] == '+') {
        problems.add('possessive');
        i += 2;
        continue;
      }
    }
    i += 1;
  }
  if (maxCaptureGroups != null && captures > maxCaptureGroups) {
    problems.add('capture_groups');
  }
  if (requireCaptureGroup && captures == 0) {
    problems.add('no_capture_group');
  }
  return problems.toList()..sort();
}
