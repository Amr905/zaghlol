// CLAUDE.md §2.4 / BR-MON-01: money code never uses floating point.
// Scans every Dart file under lib/money (generated table included) after
// removing comments and string literals, so prose and regex text cannot hide
// or fake a match.
import 'dart:io';

import 'package:test/test.dart';

/// Forbidden in code: the floating-point types and conversions, a lone `/`
/// (int / int is a double; `~/`, `//` and `/*` are fine), float literals
/// (`1.5`, `.5`, `1e3`), `toStringAsFixed` and `pow(`.
final List<RegExp> _forbidden = [
  RegExp(r'\bdouble\b'),
  RegExp(r'\bnum\b'),
  RegExp('toDouble|parseDouble|toStringAsFixed'),
  RegExp(r'\bpow\s*\('),
  RegExp(r'(?<![~/])/(?![/*])'),
  RegExp(r'\b\d+\.\d+'),
  RegExp(r'(?<![\w)\]])\.\d'),
  RegExp(r'\b\d+(\.\d+)?[eE][+-]?\d+\b'),
];

/// Replaces comments with a space and string literal text with `''`, but
/// keeps the expressions inside `${...}` interpolations (wrapped in
/// parentheses) so they are scanned like any other code.
///
/// Handles `//`, `/* */`, single, double, triple-quoted and raw strings,
/// and strings nested inside interpolations.
String stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  _copyCode(source, 0, out, false);
  return out.toString();
}

/// Copies code from [start] into [out]. In interpolation mode it stops after
/// the `}` that closes the interpolation and returns the index after it.
int _copyCode(String s, int start, StringBuffer out, bool interpolation) {
  var i = start;
  var depth = 0;
  while (i < s.length) {
    if (s.startsWith('//', i)) {
      final end = s.indexOf('\n', i);
      i = end < 0 ? s.length : end;
      continue;
    }
    if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
      out.write(' ');
      continue;
    }
    final char = s[i];
    if (char == "'" || char == '"') {
      i = _skipString(s, i, out);
      continue;
    }
    if (interpolation && char == '{') {
      depth++;
    } else if (interpolation && char == '}') {
      if (depth == 0) {
        return i + 1;
      }
      depth--;
    }
    out.write(char);
    i++;
  }
  return i;
}

/// Skips the string literal at [start], writing `''` plus the code of each
/// `${...}` interpolation; returns the index after the closing quote.
int _skipString(String s, int start, StringBuffer out) {
  final raw = start > 0 && s[start - 1] == 'r';
  final char = s[start];
  final quote = s.startsWith(char * 3, start) ? char * 3 : char;
  var j = start + quote.length;
  out.write("''");
  while (j < s.length && !s.startsWith(quote, j)) {
    if (!raw && s[j] == r'\') {
      j += 2;
    } else if (!raw && s.startsWith(r'${', j)) {
      out.write(' (');
      j = _copyCode(s, j + 2, out, true);
      out.write(') ');
    } else {
      j++;
    }
  }
  return j + quote.length;
}

List<String> violations(String source) {
  final code = stripCommentsAndStrings(source);
  final found = <String>[];
  for (final pattern in _forbidden) {
    for (final match in pattern.allMatches(code)) {
      found.add(match.group(0)!);
    }
  }
  return found;
}

void main() {
  test('lib/money contains no floating-point types or conversions', () {
    final files = <File>[];
    for (final entity in Directory('lib/money').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files.add(entity);
      }
    }
    expect(files, isNotEmpty);
    final offenders = <String>[];
    for (final file in files) {
      final found = violations(file.readAsStringSync());
      if (found.isNotEmpty) {
        offenders.add('${file.path}: ${found.join(' ')}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the scanner catches the forbidden forms', () {
    const samples = [
      'final double x = 1;',
      'num y = 2;',
      'final z = minor.toDouble();',
      'double.parse(s)',
      'num.parse(s)',
      'final q = a / b;',
      'x /= 2;',
      'final half = 0.5;',
      'final half = .5;',
      'final big = 1e3;',
      'final big = 2.5E-3;',
      'amount.toStringAsFixed(2)',
      'pow(10, exponent)',
      "final s = '\${a / b}';",
      "final s = 'EGP \${minor / 100}';",
      "final s = '\${x ? 'a' : '\${0.5}'}';",
    ];
    for (final sample in samples) {
      expect(violations(sample), isNotEmpty, reason: sample);
    }
  });

  test('the scanner ignores comments, strings and safe forms', () {
    const samples = [
      'enum Foo {}',
      'final numeric = 818;',
      'numerator',
      'final q = a ~/ b;',
      'q ~/= 2;',
      '// a / b is 0.5 as a double',
      '/// doc: 1.5 / 2',
      '/* 1e3 / 2 */ final x = 1;',
      "final s = 'a / b 0.5 double';",
      'final s = "num 1.5";',
      "final r = RegExp(r'^[0-9]+(\\.[0-9]{1,4})?\$');",
      "final t = '''multi / line 0.5''';",
      'final x = record.\$1;',
      'final y = list[0].isEven;',
      "final s = '\${a ~/ b} is 1.5 / 2 text';",
      "final s = '\${x ? 'a/b' : '0.5'}';",
      "final s = '\$name / \${map['k']}';",
    ];
    for (final sample in samples) {
      expect(violations(sample), isEmpty, reason: sample);
    }
  });
}
