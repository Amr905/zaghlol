import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib never renders a category icon string in a Text', () {
    final re = RegExp(r'Text\(\s*(?:\w+\??\.)?icon\b|Text\(\s*\w+\??\.icon\b');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/generated/') || f.path.endsWith('.g.dart')) {
        continue;
      }
      if (re.hasMatch(f.readAsStringSync())) bad.add(f.path);
    }
    expect(bad, isEmpty, reason: 'use ZCategoryGlyph/iconFor, not raw names');
  });
}
