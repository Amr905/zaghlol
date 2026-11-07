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

/// Replaces comments with a space and string literals with `''`.
///
/// Handles `//`, `/* */`, single, double, triple-quoted and raw strings.
/// Interpolated expressions inside strings are dropped with the string;
/// lib/money keeps interpolations to plain identifiers and calls.
String stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      out.write(' ');
      continue;
    }
    final char = source[i];
    if (char == "'" || char == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(char * 3, i);
      final quote = triple ? char * 3 : char;
      var j = i + quote.length;
      while (j < source.length && !source.startsWith(quote, j)) {
        j += !raw && source[j] == r'\' ? 2 : 1;
      }
      i = j + quote.length;
      out.write("''");
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
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
    ];
    for (final sample in samples) {
      expect(violations(sample), isEmpty, reason: sample);
    }
  });
}
