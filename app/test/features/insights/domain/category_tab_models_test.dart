// T-210: sorting and share rounding of the Categories tab (AC 2, 3).

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/domain/category_tab_models.dart';
import 'package:zaghlol/features/insights/domain/chart_summary.dart';
import 'package:zaghlol/features/insights/domain/overview_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');

CategoryRowData _row(String? id, int minor, {int previous = 0}) =>
    CategoryRowData(
      categoryId: id,
      amount: Money(_egp, minor),
      previousMinor: previous,
      change: ChartChange.none,
      shareBp: 0,
      count: 1,
    );

String _name(String? id) => id ?? 'Uncategorized';

List<String?> _ids(List<CategoryRowData> r) => [
  for (final x in r) x.categoryId,
];

void main() {
  group('sortCategoryRows', () {
    test('amount: largest first, ties by name then id', () {
      final out = sortCategoryRows(
        [_row('b', 100), _row('a', 100), _row('c', 300), _row(null, 100)],
        CategorySort.amount,
        _name,
      );
      expect(_ids(out), ['c', 'a', 'b', null]);
    });

    test('change: biggest absolute move first, ties by name', () {
      final out = sortCategoryRows(
        [
          _row('a', 1000, previous: 900), // 100
          _row('b', 500, previous: 1500), // 1000 (down)
          _row('c', 700, previous: 0), // 700 (new)
          _row('d', 800, previous: 700), // 100
        ],
        CategorySort.change,
        _name,
      );
      expect(_ids(out), ['b', 'c', 'a', 'd']);
    });

    test('stable for identical inputs', () {
      final rows = [_row('x', 5), _row('y', 5), _row('z', 5)];
      final a = sortCategoryRows(rows, CategorySort.amount, _name);
      final b = sortCategoryRows(
        a.reversed.toList(),
        CategorySort.amount,
        _name,
      );
      expect(_ids(a), _ids(b));
    });
  });

  group('shareStrip', () {
    int sum(List<ShareSegment> s) => s.fold(0, (a, b) => a + b.shareBp);

    test('thirds add up to exactly 10000 (largest remainder)', () {
      final s = shareStrip([_row('a', 1), _row('b', 1), _row('c', 1)]);
      expect(sum(s), 10000);
      expect([for (final x in s) x.shareBp]..sort(), [3333, 3333, 3334]);
    });

    test('at most six named segments plus Other', () {
      final rows = [for (var i = 0; i < 9; i++) _row('c$i', 1000 - i * 10)];
      final s = shareStrip(rows);
      expect(s.length, 7);
      expect(s.where((x) => x.isOther).length, 1);
      expect(s.last.isOther, isTrue);
      expect(sum(s), 10000);
    });

    test('six or fewer categories: no Other', () {
      final s = shareStrip([for (var i = 0; i < 6; i++) _row('c$i', 7 + i)]);
      expect(s.any((x) => x.isOther), isFalse);
      expect(sum(s), 10000);
    });

    test('one category is 100 %; zero spending is empty', () {
      expect(shareStrip([_row('a', 5)]).single.shareBp, 10000);
      expect(shareStrip([_row('a', 0)]), isEmpty);
      expect(shareStrip(const []), isEmpty);
    });

    test('uncategorized keeps a null id', () {
      final s = shareStrip([_row(null, 10), _row('a', 5)]);
      expect(s.first.categoryId, isNull);
      expect(s.first.isOther, isFalse);
    });
  });
}
