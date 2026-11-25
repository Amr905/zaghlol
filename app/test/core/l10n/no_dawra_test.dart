import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// T-262 / D-84: the Arabic budget period is "شهر", never "دورة".
void main() {
  test('app_ar.arb values never say دورة / الدورة / دورات', () {
    final arb = jsonDecode(
      File('lib/core/l10n/app_ar.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final word = RegExp('دور(ة|ات)');
    final bad = [
      for (final e in arb.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            word.hasMatch(e.value as String))
          e.key,
    ];
    expect(bad, isEmpty);
  });
}
