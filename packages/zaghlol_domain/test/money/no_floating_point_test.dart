// CLAUDE.md §2.4 / BR-MON-01: money code never uses floating point.
// Scans every Dart file under lib/money (generated table included).
import 'dart:io';

import 'package:test/test.dart';

final RegExp _forbidden = RegExp(r'\bdouble\b|\bnum\b|toDouble|parseDouble');

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
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_forbidden.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}');
        }
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
    ];
    for (final sample in samples) {
      expect(_forbidden.hasMatch(sample), isTrue, reason: sample);
    }
    for (final ok in ['enum Foo {}', 'final numeric = 818;', 'numerator']) {
      expect(_forbidden.hasMatch(ok), isFalse, reason: ok);
    }
  });
}
