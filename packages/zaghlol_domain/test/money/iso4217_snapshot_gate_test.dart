// Merge gate for the ISO 4217 snapshot (review finding CR2).
import 'package:test/test.dart';

import 'iso4217_test_support.dart';

void main() {
  final table = loadTable();

  group('snapshot gate (CR2)', () {
    // Fails on purpose while tool/iso4217/list-one.xml is the reconstructed
    // placeholder (published 2000-01-01). It blocks merge until a genuine
    // SIX snapshot (Amendment 180 or later) is committed with --fresh.
    test('published is a real SIX date on or after 2025-09-01', () {
      final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      expect(day.hasMatch(table.published), isTrue);
      final current = table.published.compareTo('2025-09-01') >= 0;
      expect(current, isTrue, reason: 'placeholder snapshot still in place');
    });
  });
}
