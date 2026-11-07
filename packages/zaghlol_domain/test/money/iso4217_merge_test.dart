// Generator merge guards: --fresh and the exponent/numeric guard (CR2, CR3).
import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

void main() {
  final listOne = loadListOne();

  group('merge guards (CR2, CR3)', () {
    test('without a previous table (--fresh) the result is the snapshot', () {
      final fresh = merge(listOne, null);
      expect(fresh.rows, listOne.rows);
      expect(fresh.rows.every((r) => r.active), isTrue);
    });

    test('a changed exponent or numeric throws unless allowed', () {
      final previous = gen.CurrencyTable('2025-01-01', [row('EUR', 978, 2)]);
      final newExponent = gen.CurrencyTable('2026-01-01', [row('EUR', 978, 3)]);
      final newNumeric = gen.CurrencyTable('2026-01-01', [row('EUR', 979, 2)]);
      expect(() => merge(newExponent, previous), throwsFormatException);
      expect(() => merge(newNumeric, previous), throwsFormatException);
      final allowed = mergeAllowing(newExponent, previous, {'EUR'});
      expect(allowed.rows.single.exponent, 3);
      final usd = {'USD'};
      final throws = throwsFormatException;
      expect(() => mergeAllowing(newExponent, previous, usd), throws);
      final same = gen.CurrencyTable('2026-01-01', [row('EUR', 978, 2)]);
      expect(merge(same, previous).rows.single.exponent, 2);
    });
  });
}
