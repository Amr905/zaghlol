import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  group('cycleLabelMonth (D-82)', () {
    test('start day 20 or earlier is its own month', () {
      expect(cycleLabelMonth(CivilDate(2026, 11, 1)), (year: 2026, month: 11));
      expect(cycleLabelMonth(CivilDate(2026, 11, 15)), (year: 2026, month: 11));
      expect(cycleLabelMonth(CivilDate(2026, 11, 20)), (year: 2026, month: 11));
    });

    test('start day 21 or later is the next month', () {
      expect(cycleLabelMonth(CivilDate(2026, 11, 21)), (year: 2026, month: 12));
      expect(cycleLabelMonth(CivilDate(2026, 11, 24)), (year: 2026, month: 12));
      expect(cycleLabelMonth(CivilDate(2026, 11, 28)), (year: 2026, month: 12));
    });

    test('24 Dec is January of the next year', () {
      expect(cycleLabelMonth(CivilDate(2026, 12, 24)), (year: 2027, month: 1));
      expect(cycleLabelMonth(CivilDate(2026, 12, 20)), (year: 2026, month: 12));
    });

    test('February and 31-day months follow the same rule', () {
      expect(cycleLabelMonth(CivilDate(2027, 1, 28)), (year: 2027, month: 2));
      expect(cycleLabelMonth(CivilDate(2027, 2, 28)), (year: 2027, month: 3));
    });
  });
}
