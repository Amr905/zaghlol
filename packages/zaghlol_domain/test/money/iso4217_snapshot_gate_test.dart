// Merge gate for the ISO 4217 snapshot (review finding CR2).
import 'package:test/test.dart';

import 'iso4217_test_support.dart';

void main() {
  final table = loadTable();

  group('snapshot gate (CR2)', () {
    // Guards against the reconstructed placeholder (sentinel published date
    // 2000-01-01) or any pre-Amendment-180 snapshot coming back.
    test('published is a real SIX date on or after 2025-09-01', () {
      final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      expect(day.hasMatch(table.published), isTrue);
      final current = table.published.compareTo('2025-09-01') >= 0;
      expect(current, isTrue, reason: 'placeholder snapshot still in place');
    });
  });
}
